// BlueZ по D-Bus: какие устройства подключены, кто подключился или
// отвалился, клиентский профиль под UUID канала наушников. Сокет RFCOMM
// BlueZ отдаёт профилю в NewConnection — его забирает задача устройства,
// которая ждёт в waiters.

use std::collections::HashMap;
use std::os::fd::OwnedFd;
use std::sync::{Arc, Mutex};

use futures_util::{Stream, StreamExt};
use tokio::sync::oneshot;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::{Connection, MatchRule, MessageStream};

#[derive(Clone)]
pub struct DevInfo {
    pub path: String,
    pub mac: String,
    pub name: String,
    pub uuids: Vec<String>,
    pub connected: bool,
}

type Props = HashMap<String, OwnedValue>;

fn string(props: &Props, key: &str) -> Option<String> {
    props.get(key).and_then(|v| String::try_from(v.clone()).ok())
}

fn parse(path: &str, props: &Props) -> Option<DevInfo> {
    Some(DevInfo {
        path: path.to_string(),
        mac: string(props, "Address")?.to_ascii_uppercase(),
        // Name — что объявили сами наушники; Alias может переименовать человек
        name: string(props, "Name").or_else(|| string(props, "Alias")).unwrap_or_default(),
        uuids: props
            .get("UUIDs")
            .and_then(|v| Vec::<String>::try_from(v.clone()).ok())
            .unwrap_or_default()
            .into_iter()
            .map(|u| u.to_ascii_lowercase())
            .collect(),
        connected: props.get("Connected").and_then(|v| bool::try_from(v).ok()).unwrap_or(false),
    })
}

pub async fn devices(conn: &Connection) -> zbus::Result<Vec<DevInfo>> {
    let reply = conn
        .call_method(Some("org.bluez"), "/", Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &())
        .await?;
    let objects: HashMap<OwnedObjectPath, HashMap<String, Props>> = reply.body().deserialize()?;
    Ok(objects
        .iter()
        .filter_map(|(path, ifaces)| parse(path.as_str(), ifaces.get("org.bluez.Device1")?))
        .collect())
}

pub async fn device(conn: &Connection, path: &str) -> zbus::Result<Option<DevInfo>> {
    let reply = conn
        .call_method(Some("org.bluez"), path, Some("org.freedesktop.DBus.Properties"), "GetAll", &("org.bluez.Device1",))
        .await?;
    let props: Props = reply.body().deserialize()?;
    Ok(parse(path, &props))
}

/// Изменения Connected / ServicesResolved у устройств: (путь, свойства)
pub async fn changes(conn: &Connection) -> zbus::Result<impl Stream<Item = (String, Props)>> {
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.bluez")?
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path_namespace("/org/bluez")?
        .build();
    let stream = MessageStream::for_match_rule(rule, conn, Some(64)).await?;
    Ok(stream.filter_map(|msg| async move {
        let msg = msg.ok()?;
        let path = msg.header().path()?.to_string();
        let (iface, changed, _): (String, Props, Vec<String>) = msg.body().deserialize().ok()?;
        let relevant = changed.contains_key("Connected") || changed.contains_key("ServicesResolved");
        (iface == "org.bluez.Device1" && relevant).then_some((path, changed))
    }))
}

/// bluetoothd появился на шине (запустили или перезапустили)
pub async fn restarts(conn: &Connection) -> zbus::Result<impl Stream<Item = ()> + Unpin> {
    let dbus = zbus::fdo::DBusProxy::new(conn).await?;
    let stream = dbus.receive_name_owner_changed_with_args(&[(0, "org.bluez")]).await?;
    Ok(stream.filter_map(|sig| async move {
        let args = sig.args().ok()?;
        args.new_owner().is_some().then_some(())
    }).boxed())
}

pub fn flag(props: &Props, key: &str) -> Option<bool> {
    props.get(key).and_then(|v| bool::try_from(v).ok())
}

/// Задачи устройств, ждущие свой сокет: путь устройства → куда отдать
pub type Waiters = Arc<Mutex<HashMap<String, oneshot::Sender<OwnedFd>>>>;

struct Profile {
    waiters: Waiters,
}

#[zbus::interface(name = "org.bluez.Profile1")]
impl Profile {
    fn new_connection(&self, device: OwnedObjectPath, fd: zbus::zvariant::OwnedFd, _props: Props) {
        // Никто не ждёт — сокет закроется сам, когда fd уйдёт из области
        if let Some(tx) = self.waiters.lock().unwrap().remove(device.as_str()) {
            let _ = tx.send(fd.into());
        }
    }

    fn request_disconnection(&self, _device: OwnedObjectPath) {}

    fn release(&self) {}
}

pub async fn register_profile(conn: &Connection, uuid: &str, waiters: Waiters) -> zbus::Result<()> {
    let path = format!("/org/budsd/{}", uuid.replace('-', "_"));
    conn.object_server().at(path.as_str(), Profile { waiters }).await?;

    let mut opts: HashMap<&str, Value> = HashMap::new();
    opts.insert("Role", Value::from("client"));
    opts.insert("Name", Value::from("budsd"));
    opts.insert("AutoConnect", Value::from(false));
    conn.call_method(
        Some("org.bluez"),
        "/org/bluez",
        Some("org.bluez.ProfileManager1"),
        "RegisterProfile",
        &(ObjectPath::try_from(path.as_str())?, uuid, opts),
    )
    .await?;
    Ok(())
}

pub async fn connect_profile(conn: &Connection, path: &str, uuid: &str) -> zbus::Result<()> {
    conn.call_method(Some("org.bluez"), path, Some("org.bluez.Device1"), "ConnectProfile", &(uuid,))
        .await?;
    Ok(())
}
