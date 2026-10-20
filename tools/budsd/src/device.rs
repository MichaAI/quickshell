// Задача одних наушников: открыть канал, гонять кадры по очереди, ждать
// ответы, отвечать на вызовы шелла и пересылать уведомления менеджеру.
//
// Кадры уходят по одному: после кадра с wait ждём его ответ (или таймаут),
// между любыми двумя — пауза GAP: подряд наушники глотают не всё.

use std::collections::VecDeque;
use std::io;
use std::os::fd::{AsRawFd, OwnedFd};
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::unix::AsyncFd;
use tokio::sync::{mpsc, oneshot};
use tokio::time::{sleep, sleep_until, Instant};
use zbus::Connection;

use crate::bluez::{self, DevInfo, Waiters};
use crate::drivers::{Check, Driver, Job, Out};
use crate::rpc::{self, RpcError};

const GAP: Duration = Duration::from_millis(40);
const POLL: Duration = Duration::from_secs(60);

pub enum DevCmd {
    Set { id: String, value: Value, rpc: Value },
    Act { name: String, params: Value, rpc: Value },
}

pub enum ToMgr {
    Notify { method: &'static str, params: Value },
    Reply { rpc: Value, result: Result<Value, RpcError> },
}

struct Reply {
    rpc: Value,
    check: Check,
}

struct Queued {
    job: Job,
    reply: Option<Reply>,
}

struct Pending {
    wait: &'static [u16],
    deadline: Instant,
    reply: Option<Reply>,
}

pub struct Device {
    pub info: DevInfo,
    pub driver: Box<dyn Driver>,
    pub conn: Connection,
    pub waiters: Waiters,
    /// Не удалось завести профиль под UUID драйвера — почему
    pub profile_error: Option<String>,
    pub rx: mpsc::UnboundedReceiver<DevCmd>,
    pub mgr: mpsc::UnboundedSender<(String, ToMgr)>,
}

impl Device {
    fn notify(&self, method: &'static str, params: Value) {
        let _ = self.mgr.send((self.info.mac.clone(), ToMgr::Notify { method, params }));
    }

    fn reply(&self, rpc: Value, result: Result<Value, RpcError>) {
        let _ = self.mgr.send((self.info.mac.clone(), ToMgr::Reply { rpc, result }));
    }

    fn status(&self, status: &str, message: Option<String>) {
        self.notify(
            "device",
            json!({
                "name": self.info.name,
                "status": status,
                "message": message,
                "caps": self.driver.caps(),
            }),
        );
    }

    async fn open(&self) -> Result<AsyncFd<OwnedFd>, String> {
        if let Some(e) = &self.profile_error {
            return Err(e.clone());
        }
        let uuid = self.driver.uuid();
        let (tx, mut rx) = oneshot::channel();
        self.waiters.lock().unwrap().insert(self.info.path.clone(), tx);

        // Сразу после подключения наушников канал бывает ещё не готов
        let mut last = String::from("BlueZ не открыл канал");
        let mut fd = None;
        for delay in [0, 1500, 3000, 5000] {
            sleep(Duration::from_millis(delay)).await;
            match bluez::connect_profile(&self.conn, &self.info.path, uuid).await {
                Ok(()) => {}
                // Уже открыт (например, нашим же прошлым запуском) — сокет всё равно придёт
                Err(e) if e.to_string().contains("AlreadyConnected") => {}
                Err(e) => {
                    last = format!("ConnectProfile: {e}");
                    continue;
                }
            }
            if let Ok(Ok(f)) = tokio::time::timeout(Duration::from_secs(10), &mut rx).await {
                fd = Some(f);
            }
            break;
        }
        self.waiters.lock().unwrap().remove(&self.info.path);
        let fd = fd.ok_or(last)?;

        let raw = fd.as_raw_fd();
        unsafe {
            let flags = libc::fcntl(raw, libc::F_GETFL);
            libc::fcntl(raw, libc::F_SETFL, flags | libc::O_NONBLOCK);
        }
        // SAFETY: OwnedFd владеет дескриптором и не отдаёт его, пока жив AsyncFd
        unsafe { AsyncFd::register(fd) }.map_err(|e| format!("сокет: {e}"))
    }

    pub async fn run(mut self) {
        self.status("connecting", None);
        let sock = match self.open().await {
            Ok(s) => s,
            Err(e) => {
                self.status("error", Some(e.clone()));
                // Связи нет: на вызовы отвечаем ошибкой, пока менеджер не снимет задачу
                while let Some(cmd) = self.rx.recv().await {
                    let rpc = match cmd {
                        DevCmd::Set { rpc, .. } | DevCmd::Act { rpc, .. } => rpc,
                    };
                    self.reply(rpc, Err(RpcError::new(rpc::NO_LINK, &e)));
                }
                return;
            }
        };
        self.status("ready", None);

        let mut queue: VecDeque<Queued> = self.driver.start().into_iter().map(|job| Queued { job, reply: None }).collect();
        let mut pending: Option<Pending> = None;
        let mut next_at = Instant::now();
        let mut poll = tokio::time::interval_at(Instant::now() + POLL, POLL);
        let mut buf = [0u8; 1024];

        let error = loop {
            // Отправка: пока ничего не ждём и пауза прошла
            let mut write_err = None;
            while pending.is_none() && Instant::now() >= next_at {
                let Some(q) = queue.pop_front() else { break };
                if let Err(e) = write_all(&sock, &q.job.frame).await {
                    let e = format!("запись: {e}");
                    break_with(&self, q.reply, &e);
                    write_err = Some(e);
                    break;
                }
                next_at = Instant::now() + GAP;
                if q.job.wait.is_empty() {
                    self.finish(q.reply, true);
                } else {
                    pending = Some(Pending { wait: q.job.wait, deadline: Instant::now() + q.job.timeout, reply: q.reply });
                }
            }
            if let Some(e) = write_err {
                break e;
            }

            let deadline = pending.as_ref().map(|p| p.deadline);
            let can_send = pending.is_none() && !queue.is_empty();

            tokio::select! {
                r = read(&sock, &mut buf) => {
                    let n = match r {
                        Ok(0) => break "наушники закрыли канал".to_string(),
                        Ok(n) => n,
                        Err(e) => break format!("чтение: {e}"),
                    };
                    for (cmd, payload) in self.driver.feed(&buf[..n]) {
                        for out in self.driver.handle(cmd, &payload) {
                            match out {
                                Out::Notify(method, params) => self.notify(method, params),
                                Out::Job(job) => queue.push_back(Queued { job, reply: None }),
                                Out::Caps => self.status("ready", None),
                            }
                        }
                        if pending.as_ref().is_some_and(|p| p.wait.contains(&cmd)) {
                            let p = pending.take().unwrap();
                            self.finish(p.reply, true);
                        }
                    }
                }
                cmd = self.rx.recv() => {
                    let Some(cmd) = cmd else { return };
                    let (plan, rpc) = match cmd {
                        DevCmd::Set { id, value, rpc } => (self.driver.set(&id, &value), rpc),
                        DevCmd::Act { name, params, rpc } => (self.driver.act(&name, &params), rpc),
                    };
                    match plan {
                        Err(e) => self.reply(rpc, Err(RpcError::new(rpc::INVALID_PARAMS, &e))),
                        Ok(plan) => {
                            let n = plan.jobs.len();
                            let mut reply = Some(Reply { rpc, check: plan.check });
                            if n == 0 {
                                self.finish(reply.take(), true);
                            }
                            for (i, job) in plan.jobs.into_iter().enumerate() {
                                let r = if i + 1 == n { reply.take() } else { None };
                                queue.push_back(Queued { job, reply: r });
                            }
                        }
                    }
                }
                _ = sleep_until(deadline.unwrap_or_else(Instant::now)), if deadline.is_some() => {
                    let p = pending.take().unwrap();
                    self.finish(p.reply, false);
                }
                _ = sleep_until(next_at), if can_send => {}
                _ = poll.tick() => {
                    queue.extend(self.driver.poll().into_iter().map(|job| Queued { job, reply: None }));
                }
            }
        };

        if let Some(p) = pending.take() {
            break_with(&self, p.reply, &error);
        }
        for q in queue {
            break_with(&self, q.reply, &error);
        }
        self.status("error", Some(error.clone()));
        while let Some(cmd) = self.rx.recv().await {
            let rpc = match cmd {
                DevCmd::Set { rpc, .. } | DevCmd::Act { rpc, .. } => rpc,
            };
            self.reply(rpc, Err(RpcError::new(rpc::NO_LINK, &error)));
        }
    }

    /// Последний кадр плана отработал (ok) или не дождался ответа
    fn finish(&self, reply: Option<Reply>, ok: bool) {
        let Some(Reply { rpc, check }) = reply else { return };
        let result = match check {
            Check::Value(id, want) => {
                let actual = self.driver.value(&id).unwrap_or(Value::Null);
                if ok && actual == want {
                    Ok(json!({ "value": want }))
                } else {
                    // С тем, что на самом деле в наушниках, — к нему шелл и откатится
                    let (code, msg) = if ok {
                        (rpc::REJECTED, "наушники не приняли настройку")
                    } else {
                        (rpc::TIMEOUT, "наушники не ответили")
                    };
                    Err(RpcError::new(code, msg).with(json!({ "id": id, "value": actual })))
                }
            }
            Check::Fit if ok => Ok(self.driver.fit()),
            Check::Done if ok => Ok(Value::Null),
            _ => Err(RpcError::new(rpc::TIMEOUT, "наушники не ответили")),
        };
        self.reply(rpc, result);
    }
}

fn break_with(dev: &Device, reply: Option<Reply>, why: &str) {
    if let Some(r) = reply {
        dev.reply(r.rpc, Err(RpcError::new(rpc::NO_LINK, why)));
    }
}

async fn read(sock: &AsyncFd<OwnedFd>, buf: &mut [u8]) -> io::Result<usize> {
    loop {
        let mut guard = sock.readable().await?;
        let r = guard.try_io(|fd| {
            let n = unsafe { libc::read(fd.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
            if n < 0 {
                Err(io::Error::last_os_error())
            } else {
                Ok(n as usize)
            }
        });
        if let Ok(r) = r {
            return r;
        }
    }
}

async fn write_all(sock: &AsyncFd<OwnedFd>, mut data: &[u8]) -> io::Result<()> {
    while !data.is_empty() {
        let mut guard = sock.writable().await?;
        let r = guard.try_io(|fd| {
            let n = unsafe { libc::write(fd.as_raw_fd(), data.as_ptr().cast(), data.len()) };
            if n < 0 {
                Err(io::Error::last_os_error())
            } else {
                Ok(n as usize)
            }
        });
        if let Ok(r) = r {
            data = &data[r?..];
        }
    }
    Ok(())
}
