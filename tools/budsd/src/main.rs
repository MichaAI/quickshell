// budsd — демон наушников для шелла. Живёт всё время: следит за BlueZ, сам
// открывает канал управления к подключённым наушникам, для которых есть
// драйвер, и говорит с шеллом по JSON-RPC 2.0 (по сообщению на строку в
// stdin/stdout). Наушники называются по MAC ("device").
//
// Вызовы (шелл → budsd):
//   list                              → [{device, name, status, message, caps,
//                                         values, battery, devices, info}]
//   set {device, id, value}           → {value}; ответ — когда наушники
//                                       подтвердили. Ошибка 3/4 несёт в data
//                                       {id, value} — что в них на самом деле
//   ring {device, side, on}           → null
//   fitTest {device}                  → {left, right}: good | bad | error
//   dualConnect {device, mac, connect} → null
//   refresh {device}                  → null: перечитать всё
//   reconnect {device}                → null: заново открыть канал
// Уведомления (budsd → шелл), у всех есть device:
//   device  {name, status, message?, caps}: status — connecting, ready,
//           error, gone (отключились)
//   value   {id, value}
//   battery {left|right|case|single: {level, charging}}
//   devices {list: [{mac, name, connected, self}]}: к чему подключены уши
//   info    {firmware}
//
// Драйверы и описание контролов — в drivers/.

mod bluez;
mod device;
mod drivers;
mod rpc;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use futures_util::StreamExt;
use serde_json::{json, Map, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

use bluez::{DevInfo, Waiters};
use device::{DevCmd, Device, ToMgr};
use rpc::RpcError;

enum Ev {
    /// bluetoothd запустился заново: профили и устройства — с нуля
    Restarted,
    Changed(String, HashMap<String, zbus::zvariant::OwnedValue>),
    Dev(String, ToMgr),
    Rpc(String),
    Quit,
}

/// Наушники, которые сейчас ведёт демон, и последнее известное о них
struct Tracked {
    info: DevInfo,
    tx: mpsc::UnboundedSender<DevCmd>,
    task: JoinHandle<()>,
    snapshot: Map<String, Value>,
}

struct Manager {
    conn: zbus::Connection,
    waiters: Waiters,
    profile_errors: HashMap<&'static str, String>,
    out: mpsc::UnboundedSender<Value>,
    dev_tx: mpsc::UnboundedSender<(String, ToMgr)>,
    /// По пути устройства в BlueZ
    tracked: HashMap<String, Tracked>,
}

impl Manager {
    async fn register(&mut self) {
        self.profile_errors.clear();
        for uuid in drivers::uuids() {
            if let Err(e) = bluez::register_profile(&self.conn, uuid, self.waiters.clone()).await {
                // Тот же UUID уже занял кто-то другой (BudsLink, второй budsd…)
                let msg = format!("не удалось завести профиль {uuid}: {e}");
                eprintln!("budsd: {msg}");
                self.profile_errors.insert(uuid, msg);
            }
        }
    }

    async fn rescan(&mut self) {
        for path in self.tracked.keys().cloned().collect::<Vec<_>>() {
            self.drop_device(&path);
        }
        self.register().await;
        match bluez::devices(&self.conn).await {
            Ok(list) => list.into_iter().for_each(|d| self.spawn(d)),
            Err(e) => eprintln!("budsd: BlueZ: {e}"),
        }
    }

    fn notify(&self, method: &str, params: Value) {
        let _ = self.out.send(rpc::notification(method, params));
    }

    fn spawn(&mut self, info: DevInfo) {
        if !info.connected || self.tracked.contains_key(&info.path) {
            return;
        }
        let Some(driver) = drivers::pick(&info.name, &info.uuids) else { return };
        let (tx, rx) = mpsc::unbounded_channel();
        let dev = Device {
            info: info.clone(),
            profile_error: self.profile_errors.get(driver.uuid()).cloned(),
            driver,
            conn: self.conn.clone(),
            waiters: self.waiters.clone(),
            rx,
            mgr: self.dev_tx.clone(),
        };
        let task = tokio::spawn(dev.run());
        let mut snapshot = Map::new();
        snapshot.insert("device".into(), json!(info.mac));
        self.tracked.insert(info.path.clone(), Tracked { info, tx, task, snapshot });
    }

    fn drop_device(&mut self, path: &str) {
        if let Some(t) = self.tracked.remove(path) {
            t.task.abort();
            self.waiters.lock().unwrap().remove(path);
            self.notify("device", json!({ "device": t.info.mac, "name": t.info.name, "status": "gone" }));
        }
    }

    async fn changed(&mut self, path: String, props: HashMap<String, zbus::zvariant::OwnedValue>) {
        if bluez::flag(&props, "Connected") == Some(false) {
            self.drop_device(&path);
            return;
        }
        if self.tracked.contains_key(&path) {
            return;
        }
        // Подключились или BlueZ дочитал сервисы (UUID) — может, это наши
        if let Ok(Some(info)) = bluez::device(&self.conn, &path).await {
            self.spawn(info);
        }
    }

    fn on_device(&mut self, mac: String, msg: ToMgr) {
        match msg {
            ToMgr::Reply { rpc, result } => {
                let _ = self.out.send(rpc::response(rpc, result));
            }
            ToMgr::Notify { method, mut params } => {
                if let Some(t) = self.tracked.values_mut().find(|t| t.info.mac == mac) {
                    let snap = &mut t.snapshot;
                    match method {
                        "device" => {
                            for (k, v) in params.as_object().into_iter().flatten() {
                                snap.insert(k.clone(), v.clone());
                            }
                        }
                        "value" => {
                            let values = snap.entry("values").or_insert(json!({}));
                            if let Some(id) = params["id"].as_str() {
                                values[id] = params["value"].clone();
                            }
                        }
                        "battery" | "info" => {
                            let entry = snap.entry(method).or_insert(json!({}));
                            for (k, v) in params.as_object().into_iter().flatten() {
                                entry[k] = v.clone();
                            }
                        }
                        "devices" => {
                            snap.insert("devices".into(), params["list"].clone());
                        }
                        _ => {}
                    }
                }
                params["device"] = json!(mac);
                self.notify(method, params);
            }
        }
    }

    fn by_mac(&self, params: &Value) -> Result<&Tracked, RpcError> {
        let mac = params["device"].as_str().ok_or_else(|| RpcError::new(rpc::INVALID_PARAMS, "нужен device"))?;
        self.tracked
            .values()
            .find(|t| t.info.mac.eq_ignore_ascii_case(mac))
            .ok_or_else(|| RpcError::new(rpc::NO_DEVICE, &format!("нет подключённых наушников {mac}")))
    }

    fn request(&mut self, line: &str) {
        let req = match rpc::parse(line) {
            Ok(r) => r,
            Err(resp) => {
                let _ = self.out.send(resp);
                return;
            }
        };
        let id = req.id.clone().unwrap_or(Value::Null);
        let p = &req.params;
        let result: Result<Option<Value>, RpcError> = (|| match req.method.as_str() {
            "list" => Ok(Some(self.tracked.values().map(|t| Value::Object(t.snapshot.clone())).collect())),
            "set" => {
                let t = self.by_mac(p)?;
                let key = p["id"].as_str().ok_or_else(|| RpcError::new(rpc::INVALID_PARAMS, "нужен id"))?;
                let cmd = DevCmd::Set { id: key.to_string(), value: p["value"].clone(), rpc: id.clone() };
                t.tx.send(cmd).map_err(|_| RpcError::new(rpc::NO_LINK, "нет связи с наушниками"))?;
                Ok(None)
            }
            "ring" | "fitTest" | "dualConnect" | "refresh" => {
                let t = self.by_mac(p)?;
                let cmd = DevCmd::Act { name: req.method.clone(), params: p.clone(), rpc: id.clone() };
                t.tx.send(cmd).map_err(|_| RpcError::new(rpc::NO_LINK, "нет связи с наушниками"))?;
                Ok(None)
            }
            "reconnect" => {
                let info = self.by_mac(p)?.info.clone();
                self.drop_device(&info.path);
                self.spawn(info);
                Ok(Some(Value::Null))
            }
            m => Err(RpcError::new(rpc::METHOD_NOT_FOUND, &format!("нет метода {m}"))),
        })();
        // None — ответит задача наушников, когда они подтвердят
        let reply = match result {
            Ok(None) => return,
            Ok(Some(v)) => Ok(v),
            Err(e) => Err(e),
        };
        if req.id.is_some() {
            let _ = self.out.send(rpc::response(id, reply));
        }
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let (out, mut out_rx) = mpsc::unbounded_channel::<Value>();
    tokio::spawn(async move {
        let mut stdout = tokio::io::stdout();
        while let Some(v) = out_rx.recv().await {
            let line = format!("{v}\n");
            if stdout.write_all(line.as_bytes()).await.is_err() || stdout.flush().await.is_err() {
                std::process::exit(0);
            }
        }
    });

    let conn = match zbus::Connection::system().await {
        Ok(c) => c,
        Err(e) => {
            eprintln!("budsd: system bus: {e}");
            std::process::exit(1);
        }
    };

    let waiters: Waiters = Arc::new(Mutex::new(HashMap::new()));

    let (ev_tx, mut ev) = mpsc::unbounded_channel::<Ev>();
    let (dev_tx, mut dev_rx) = mpsc::unbounded_channel::<(String, ToMgr)>();

    let tx = ev_tx.clone();
    tokio::spawn(async move {
        while let Some((mac, msg)) = dev_rx.recv().await {
            let _ = tx.send(Ev::Dev(mac, msg));
        }
    });

    match bluez::changes(&conn).await {
        Ok(stream) => {
            let mut stream = Box::pin(stream);
            let tx = ev_tx.clone();
            tokio::spawn(async move {
                while let Some((path, props)) = stream.next().await {
                    let _ = tx.send(Ev::Changed(path, props));
                }
            });
        }
        Err(e) => eprintln!("budsd: не слышно BlueZ: {e}"),
    }

    if let Ok(mut owners) = bluez::restarts(&conn).await {
        let tx = ev_tx.clone();
        tokio::spawn(async move {
            while owners.next().await.is_some() {
                let _ = tx.send(Ev::Restarted);
            }
        });
    }

    let tx = ev_tx.clone();
    tokio::spawn(async move {
        let mut lines = BufReader::new(tokio::io::stdin()).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if !line.trim().is_empty() {
                let _ = tx.send(Ev::Rpc(line));
            }
        }
        // Шелл закрыл stdin — значит, нас больше не слушают
        let _ = tx.send(Ev::Quit);
    });

    let mut mgr = Manager { conn, waiters, profile_errors: HashMap::new(), out, dev_tx, tracked: HashMap::new() };
    mgr.rescan().await;

    while let Some(e) = ev.recv().await {
        match e {
            Ev::Restarted => mgr.rescan().await,
            Ev::Changed(path, props) => mgr.changed(path, props).await,
            Ev::Dev(mac, msg) => mgr.on_device(mac, msg),
            Ev::Rpc(line) => mgr.request(&line),
            Ev::Quit => break,
        }
    }
}
