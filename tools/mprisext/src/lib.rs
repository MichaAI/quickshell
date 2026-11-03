//! QML-плагин `MichaAI.Mpris`: элемент `MprisExt` читает у плеера
//! расширение `org.mpris.MediaPlayer2.MichaAIext` (на том же объекте
//! `/org/mpris/MediaPlayer2`, что и MPRIS) и зовёт его методы.
//!
//! Интерфейс плеера:
//!   Left(), Right()   — нажатия кнопок расширения
//!   LeftIcon   s      — SVG левой кнопки, "" — кнопки нет
//!   RightIcon  s      — то же для правой
//!   Lyrics     (os)   — (mpris:trackid трека, текст LRC)
//!   + PropertiesChanged на каждую смену
//!
//! Текст отдаётся в QML, только если его trackid совпал с mpris:trackid
//! в Metadata плеера: на смене трека старый текст не мелькает.
//!
//! D-Bus — в своём потоке на zbus, без внешних процессов. Поток спит на
//! сокете шины, пока плеер не пришлёт сигнал или QML не попросит действие;
//! значения уходят в поток Qt через `qt_thread().queue`.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, service, READ, WRITE = set_service, NOTIFY)]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(QString, left_icon, cxx_name = "leftIcon", READ, NOTIFY)]
        #[qproperty(QString, right_icon, cxx_name = "rightIcon", READ, NOTIFY)]
        #[qproperty(QString, lyrics, READ, NOTIFY)]
        type MprisExt = super::MprisExtRust;

        #[cxx_name = "setService"]
        fn set_service(self: Pin<&mut Self>, service: QString);

        #[qinvokable]
        fn left(self: &MprisExt);

        #[qinvokable]
        fn right(self: &MprisExt);
    }

    impl cxx_qt::Threading for MprisExt {}
    impl cxx_qt::Initialize for MprisExt {}
}

use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_util::{stream, StreamExt};
use std::collections::HashMap;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

const PATH: &str = "/org/mpris/MediaPlayer2";
const IFACE: &str = "org.mpris.MediaPlayer2.MichaAIext";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

enum Cmd {
    Service(String, u64),
    Call(&'static str),
}

#[derive(Default)]
struct State {
    available: bool,
    left: String,
    right: String,
    lyrics: String,
}

#[derive(Default)]
pub struct MprisExtRust {
    service: QString,
    available: bool,
    left_icon: QString,
    right_icon: QString,
    lyrics: QString,
    // Поколение: ответы для прежнего плеера, пришедшие после смены, не в счёт
    generation: u64,
    // Закрытие канала (элемент удалён) останавливает поток
    cmds: Option<async_channel::Sender<Cmd>>,
}

impl cxx_qt::Initialize for qobject::MprisExt {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::unbounded();
        self.as_mut().rust_mut().cmds = Some(tx);
        let qt = self.qt_thread();
        let spawned = std::thread::Builder::new()
            .name("mprisext".into())
            .spawn(move || {
                if let Err(e) = async_io::block_on(worker(rx, qt)) {
                    eprintln!("mprisext: {e}");
                }
            });
        if let Err(e) = spawned {
            eprintln!("mprisext: поток не запустился: {e}");
        }
    }
}

impl qobject::MprisExt {
    pub fn set_service(mut self: Pin<&mut Self>, service: QString) {
        if service == self.service {
            return;
        }
        let generation = self.generation + 1;
        let name = service.to_string();
        {
            let mut r = self.as_mut().rust_mut();
            r.generation = generation;
            r.service = service;
        }
        self.as_mut().service_changed();
        // Прежний плеер больше не наш — сразу пусто, новое придёт из потока
        self.as_mut().apply(State::default());
        self.send(Cmd::Service(name, generation));
    }

    pub fn left(&self) {
        self.send(Cmd::Call("Left"));
    }

    pub fn right(&self) {
        self.send(Cmd::Call("Right"));
    }

    fn send(&self, cmd: Cmd) {
        if let Some(tx) = &self.cmds {
            let _ = tx.try_send(cmd);
        }
    }

    fn apply(mut self: Pin<&mut Self>, s: State) {
        if self.available != s.available {
            self.as_mut().rust_mut().available = s.available;
            self.as_mut().available_changed();
        }
        macro_rules! put {
            ($field:ident, $notify:ident, $value:expr) => {{
                let v = QString::from(&$value);
                if self.$field != v {
                    self.as_mut().rust_mut().$field = v;
                    self.as_mut().$notify();
                }
            }};
        }
        put!(left_icon, left_icon_changed, s.left);
        put!(right_icon, right_icon_changed, s.right);
        put!(lyrics, lyrics_changed, s.lyrics);
    }
}

enum Ev {
    Cmd(Cmd),
    Changed,
    Quit,
}

async fn worker(
    rx: async_channel::Receiver<Cmd>,
    qt: cxx_qt::CxxQtThread<qobject::MprisExt>,
) -> zbus::Result<()> {
    let conn = zbus::Connection::session().await?;
    let dbus = zbus::fdo::DBusProxy::new(&conn).await?;
    let mut service = String::new();
    let mut generation = 0u64;

    let push = |s: State, generation: u64| {
        let _ = qt.queue(move |o| {
            if o.generation == generation {
                o.apply(s);
            }
        });
    };

    loop {
        let cmds = rx.clone().map(Ev::Cmd).chain(stream::once(async { Ev::Quit }));
        let mut events: stream::BoxStream<'_, Ev> = if service.is_empty() {
            cmds.boxed()
        } else {
            match subscribe(&conn, &dbus, &service).await {
                Ok(watch) => stream::select(cmds, watch).boxed(),
                Err(e) => {
                    eprintln!("mprisext: {service}: {e}");
                    cmds.boxed()
                }
            }
        };
        if !service.is_empty() {
            push(read(&conn, &service).await, generation);
        }

        while let Some(ev) = events.next().await {
            match ev {
                Ev::Quit => return Ok(()),
                Ev::Changed => push(read(&conn, &service).await, generation),
                Ev::Cmd(Cmd::Call(method)) => {
                    if !service.is_empty() {
                        let r = conn
                            .call_method(Some(service.as_str()), PATH, Some(IFACE), method, &())
                            .await;
                        if let Err(e) = r {
                            eprintln!("mprisext: {service}.{method}: {e}");
                        }
                    }
                }
                Ev::Cmd(Cmd::Service(s, g)) => {
                    service = s;
                    generation = g;
                    break;
                }
            }
        }
    }
}

/// Сигналы, после которых надо перечитать свойства: смена свойств нашего
/// интерфейса, смена трека (Metadata у MPRIS) и смена владельца имени
/// (плеер перезапустился или закрылся)
async fn subscribe(
    conn: &zbus::Connection,
    dbus: &zbus::fdo::DBusProxy<'_>,
    service: &str,
) -> zbus::Result<stream::BoxStream<'static, Ev>> {
    let props = zbus::fdo::PropertiesProxy::builder(conn)
        .destination(service.to_owned())?
        .path(PATH)?
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await?;
    let changed = props
        .receive_properties_changed()
        .await?
        .filter(|sig| {
            let ours = sig
                .args()
                .map(|a| match a.interface_name.as_str() {
                    IFACE => true,
                    PLAYER => a.changed_properties.contains_key("Metadata"),
                    _ => false,
                })
                .unwrap_or(false);
            async move { ours }
        })
        .map(|_| Ev::Changed);
    let owner = dbus
        .receive_name_owner_changed_with_args(&[(0, service)])
        .await?
        .map(|_| Ev::Changed);
    Ok(stream::select(changed, owner).boxed())
}

async fn get_all(conn: &zbus::Connection, service: &str, iface: &str) -> Option<HashMap<String, OwnedValue>> {
    let reply = conn
        .call_method(Some(service), PATH, Some("org.freedesktop.DBus.Properties"), "GetAll", &(iface,))
        .await
        .ok()?;
    reply.body().deserialize().ok()
}

/// mpris:trackid трека, который играет сейчас
async fn current_track(conn: &zbus::Connection, service: &str) -> Option<String> {
    let reply = conn
        .call_method(Some(service), PATH, Some("org.freedesktop.DBus.Properties"), "Get", &(PLAYER, "Metadata"))
        .await
        .ok()?;
    let body = reply.body();
    let meta: OwnedValue = body.deserialize().ok()?;
    let meta: HashMap<String, OwnedValue> = match &*meta {
        zbus::zvariant::Value::Value(v) => OwnedValue::try_from(&**v).ok()?.try_into().ok()?,
        _ => meta.try_into().ok()?,
    };
    let id = meta.get("mpris:trackid")?.try_clone().ok()?;
    OwnedObjectPath::try_from(id).ok().map(|p| p.to_string())
}

/// Все свойства разом; нет интерфейса или плеера — пусто
async fn read(conn: &zbus::Connection, service: &str) -> State {
    let Some(all) = get_all(conn, service, IFACE).await else {
        return State::default();
    };
    let text = |k: &str| {
        all.get(k)
            .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
            .unwrap_or_default()
    };
    let (track, lyrics) = all
        .get("Lyrics")
        .and_then(|v| <(OwnedObjectPath, String)>::try_from(v.try_clone().ok()?).ok())
        .map(|(t, l)| (t.to_string(), l))
        .unwrap_or_default();
    // Текст чужого (прошлого) трека не показываем
    let lyrics = if !lyrics.is_empty() && current_track(conn, service).await.as_deref() == Some(track.as_str()) {
        lyrics
    } else {
        String::new()
    };
    State {
        available: true,
        left: text("LeftIcon"),
        right: text("RightIcon"),
        lyrics,
    }
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
        fn mprisext_qt_plugin_instance() -> *mut c_void;
        fn mprisext_qt_plugin_query_metadata_v2() -> QPluginMetaData;
    }

    #[no_mangle]
    pub extern "C" fn qt_plugin_instance() -> *mut c_void {
        unsafe { mprisext_qt_plugin_instance() }
    }

    #[no_mangle]
    pub extern "C" fn qt_plugin_query_metadata_v2() -> QPluginMetaData {
        unsafe { mprisext_qt_plugin_query_metadata_v2() }
    }
}
