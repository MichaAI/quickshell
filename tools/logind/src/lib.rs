//! QML-плагин `MichaAI.Logind`: элемент `Logind` — то, что шеллу нужно от
//! systemd-logind для простоя и лока.
//!
//!   blocked     s     — BlockInhibited: что сейчас запрещено ("idle:sleep")
//!   inhibitors  s     — кто запрещает: JSON [{what, who, why}] блокирующих
//!                       инхибиторов (служебные handle-* не в счёт)
//!   locked      b     — LockedHint сессии (пишет QML)
//!   idle        b     — IdleHint сессии (пишет QML)
//!   guardSleep  b     — держать delay-инхибитор сна: logind ждёт
//!                       sleepReady() (не дольше InhibitDelayMaxSec), прежде
//!                       чем усыпить
//!   prepareForSleep(start) — сейчас уснём / проснулись
//!   lockRequested()        — loginctl lock-session
//!
//! D-Bus — в своём потоке на zbus, по сигналам, без процессов и опроса.
//! Значения уходят в поток Qt через `qt_thread().queue`.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(QString, blocked, READ, NOTIFY)]
        #[qproperty(QString, inhibitors, READ, NOTIFY)]
        #[qproperty(bool, locked, READ, WRITE = set_locked, NOTIFY)]
        #[qproperty(bool, idle, READ, WRITE = set_idle, NOTIFY)]
        #[qproperty(bool, guard_sleep, cxx_name = "guardSleep", READ, WRITE = set_guard_sleep, NOTIFY)]
        type Logind = super::LogindRust;

        #[cxx_name = "setLocked"]
        fn set_locked(self: Pin<&mut Self>, value: bool);

        #[cxx_name = "setIdle"]
        fn set_idle(self: Pin<&mut Self>, value: bool);

        #[cxx_name = "setGuardSleep"]
        fn set_guard_sleep(self: Pin<&mut Self>, value: bool);

        /// Экран закрыт — можно спать
        #[qinvokable]
        #[cxx_name = "sleepReady"]
        fn sleep_ready(self: &Logind);

        #[qsignal]
        #[cxx_name = "prepareForSleep"]
        fn prepare_for_sleep(self: Pin<&mut Logind>, start: bool);

        #[qsignal]
        #[cxx_name = "lockRequested"]
        fn lock_requested(self: Pin<&mut Logind>);
    }

    impl cxx_qt::Threading for Logind {}
    impl cxx_qt::Initialize for Logind {}
}

use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_util::{stream, StreamExt};
use zbus::zvariant::{OwnedFd, OwnedObjectPath};

const DEST: &str = "org.freedesktop.login1";
const PATH: &str = "/org/freedesktop/login1";
const MANAGER: &str = "org.freedesktop.login1.Manager";
const SESSION: &str = "org.freedesktop.login1.Session";

enum Cmd {
    Locked(bool),
    Idle(bool),
    Guard(bool),
    SleepReady,
}

#[derive(Default)]
pub struct LogindRust {
    available: bool,
    blocked: QString,
    inhibitors: QString,
    locked: bool,
    idle: bool,
    guard_sleep: bool,
    // Закрытие канала (элемент удалён) останавливает поток
    cmds: Option<async_channel::Sender<Cmd>>,
}

impl cxx_qt::Initialize for qobject::Logind {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::unbounded();
        self.as_mut().rust_mut().cmds = Some(tx);
        let qt = self.qt_thread();
        let spawned = std::thread::Builder::new()
            .name("logind".into())
            .spawn(move || {
                if let Err(e) = async_io::block_on(worker(rx, qt)) {
                    eprintln!("logind: {e}");
                }
            });
        if let Err(e) = spawned {
            eprintln!("logind: поток не запустился: {e}");
        }
    }
}

impl qobject::Logind {
    pub fn set_locked(mut self: Pin<&mut Self>, value: bool) {
        if self.locked != value {
            self.as_mut().rust_mut().locked = value;
            self.as_mut().locked_changed();
        }
        // Шлём и без смены: подсказку мог сбросить кто-то другой
        self.send(Cmd::Locked(value));
    }

    pub fn set_idle(mut self: Pin<&mut Self>, value: bool) {
        if self.idle != value {
            self.as_mut().rust_mut().idle = value;
            self.as_mut().idle_changed();
            self.send(Cmd::Idle(value));
        }
    }

    pub fn set_guard_sleep(mut self: Pin<&mut Self>, value: bool) {
        if self.guard_sleep != value {
            self.as_mut().rust_mut().guard_sleep = value;
            self.as_mut().guard_sleep_changed();
            self.send(Cmd::Guard(value));
        }
    }

    pub fn sleep_ready(&self) {
        self.send(Cmd::SleepReady);
    }

    fn send(&self, cmd: Cmd) {
        if let Some(tx) = &self.cmds {
            let _ = tx.try_send(cmd);
        }
    }

    fn apply(mut self: Pin<&mut Self>, blocked: String, inhibitors: String) {
        if !self.available {
            self.as_mut().rust_mut().available = true;
            self.as_mut().available_changed();
        }
        // Сначала список: на смене blocked QML читает уже свежий
        let inhibitors = QString::from(&inhibitors);
        if self.inhibitors != inhibitors {
            self.as_mut().rust_mut().inhibitors = inhibitors;
            self.as_mut().inhibitors_changed();
        }
        let blocked = QString::from(&blocked);
        if self.blocked != blocked {
            self.as_mut().rust_mut().blocked = blocked;
            self.as_mut().blocked_changed();
        }
    }
}

enum Ev {
    Cmd(Cmd),
    Changed,
    Sleep(bool),
    Lock,
    Quit,
}

async fn worker(
    rx: async_channel::Receiver<Cmd>,
    qt: cxx_qt::CxxQtThread<qobject::Logind>,
) -> zbus::Result<()> {
    let conn = zbus::Connection::system().await?;
    let manager = proxy(&conn, PATH, MANAGER).await?;
    let props = zbus::fdo::PropertiesProxy::builder(&conn)
        .destination(DEST)?
        .path(PATH)?
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await?;

    // Наша сессия: шелл — служба systemd --user, своей сессии у процесса
    // нет, и "auto" даёт графическую сессию пользователя
    let session = match manager.call::<_, _, OwnedObjectPath>("GetSession", &("auto",)).await {
        Ok(path) => Some(proxy(&conn, path.as_str(), SESSION).await?),
        Err(e) => {
            eprintln!("logind: нет сессии: {e}");
            None
        }
    };

    let changed = props
        .receive_properties_changed()
        .await?
        .filter(|sig| {
            let ours = sig
                .args()
                .map(|a| a.interface_name.as_str() == MANAGER && a.changed_properties.contains_key("BlockInhibited"))
                .unwrap_or(false);
            async move { ours }
        })
        .map(|_| Ev::Changed)
        .boxed();
    let sleep = manager
        .receive_signal("PrepareForSleep")
        .await?
        .map(|m| Ev::Sleep(m.body().deserialize::<bool>().unwrap_or(false)))
        .boxed();
    let lock = match &session {
        Some(s) => s.receive_signal("Lock").await?.map(|_| Ev::Lock).boxed(),
        None => stream::empty().boxed(),
    };
    let cmds = rx.map(Ev::Cmd).chain(stream::once(async { Ev::Quit })).boxed();
    let mut events = stream::select(stream::select(cmds, changed), stream::select(sleep, lock));

    let push = |(blocked, inhibitors): (String, String)| {
        let _ = qt.queue(move |o| o.apply(blocked, inhibitors));
    };
    push(read(&manager).await);

    let mut guard = false;
    let mut sleeping = false;
    let mut delay: Option<OwnedFd> = None;

    while let Some(ev) = events.next().await {
        match ev {
            Ev::Quit => return Ok(()),
            Ev::Changed => push(read(&manager).await),
            Ev::Lock => {
                let _ = qt.queue(|o| o.lock_requested());
            }
            Ev::Sleep(start) => {
                sleeping = start;
                // Проснулись — инхибитор на следующий сон
                if !start && guard && delay.is_none() {
                    delay = inhibit(&manager).await;
                }
                let _ = qt.queue(move |o| o.prepare_for_sleep(start));
            }
            Ev::Cmd(Cmd::SleepReady) => delay = None,
            Ev::Cmd(Cmd::Guard(on)) => {
                guard = on;
                if !on {
                    delay = None;
                } else if !sleeping && delay.is_none() {
                    delay = inhibit(&manager).await;
                }
            }
            Ev::Cmd(Cmd::Locked(on)) => hint(&session, "SetLockedHint", on).await,
            Ev::Cmd(Cmd::Idle(on)) => hint(&session, "SetIdleHint", on).await,
        }
    }
    Ok(())
}

async fn proxy<'a>(conn: &zbus::Connection, path: &str, iface: &'static str) -> zbus::Result<zbus::Proxy<'a>> {
    zbus::proxy::Builder::new(conn)
        .destination(DEST)?
        .path(path.to_owned())?
        .interface(iface)?
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await
}

async fn hint(session: &Option<zbus::Proxy<'_>>, method: &str, on: bool) {
    if let Some(s) = session {
        if let Err(e) = s.call_method(method, &(on,)).await {
            eprintln!("logind: {method}: {e}");
        }
    }
}

async fn inhibit(manager: &zbus::Proxy<'_>) -> Option<OwnedFd> {
    manager
        .call::<_, _, OwnedFd>("Inhibit", &("sleep", "quickshell", "Закрыть экран перед сном", "delay"))
        .await
        .map_err(|e| eprintln!("logind: Inhibit: {e}"))
        .ok()
}

/// BlockInhibited и JSON блокирующих инхибиторов
async fn read(manager: &zbus::Proxy<'_>) -> (String, String) {
    let blocked: String = manager.get_property("BlockInhibited").await.unwrap_or_default();
    let list: Vec<(String, String, String, String, u32, u32)> =
        manager.call("ListInhibitors", &()).await.unwrap_or_default();
    let items: Vec<String> = list
        .into_iter()
        .filter_map(|(what, who, why, mode, _uid, _pid)| {
            let what: Vec<&str> = what.split(':').filter(|w| !w.starts_with("handle-")).collect();
            (mode == "block" && !what.is_empty()).then(|| {
                format!(
                    r#"{{"what":{},"who":{},"why":{}}}"#,
                    json(&what.join(":")),
                    json(&who),
                    json(&why)
                )
            })
        })
        .collect();
    (blocked, format!("[{}]", items.join(",")))
}

fn json(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Точки входа плагина Qt. C++ определяет их под другими именами (см.
/// build.rs): cdylib от rustc экспортирует только символы Rust
mod plugin_entry {
    use std::ffi::c_void;

    #[repr(C)]
    pub struct QPluginMetaData {
        data: *const c_void,
        size: usize,
    }

    extern "C" {
        fn logind_qt_plugin_instance() -> *mut c_void;
        fn logind_qt_plugin_query_metadata_v2() -> QPluginMetaData;
    }

    #[no_mangle]
    pub extern "C" fn qt_plugin_instance() -> *mut c_void {
        unsafe { logind_qt_plugin_instance() }
    }

    #[no_mangle]
    pub extern "C" fn qt_plugin_query_metadata_v2() -> QPluginMetaData {
        unsafe { logind_qt_plugin_query_metadata_v2() }
    }
}
