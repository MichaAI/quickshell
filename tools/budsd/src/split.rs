// ZMK-сплит (Lily58 и т. п.) по BLE: канала управления у клавиатуры нет,
// есть только заряд половин. Центральная отдаёт свой заряд обычным Battery
// Level, а заряд остальных — прокси ZMK
// (CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY): ещё один Battery Level
// с описанием (2901) «Peripheral N». BlueZ показывает только первый, поэтому
// оба читаем сами и подписываемся на уведомления.
//
// Центральная у ZMK обычно левая — её и зовём left, Peripheral 0 — right.

use std::collections::HashMap;

use futures_util::StreamExt;
use serde_json::{json, Value};
use tokio::sync::mpsc;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};
use zbus::{Connection, MatchRule, MessageStream};

use crate::bluez::DevInfo;
use crate::device::{DevCmd, ToMgr};
use crate::rpc::{self, RpcError};

const BATTERY_LEVEL: &str = "00002a19-0000-1000-8000-00805f9b34fb";
const USER_DESCRIPTION: &str = "00002901-0000-1000-8000-00805f9b34fb";
const CHAR_IFACE: &str = "org.bluez.GattCharacteristic1";
const DESC_IFACE: &str = "org.bluez.GattDescriptor1";

/// Пути характеристик заряда: своей у центральной и прокси первой периферии
pub struct Halves {
    central: String,
    peripheral: String,
}

type Props = HashMap<String, OwnedValue>;
type Objects = HashMap<OwnedObjectPath, HashMap<String, Props>>;

fn uuid(props: &Props) -> Option<String> {
    props.get("UUID").and_then(|v| String::try_from(v.clone()).ok()).map(|u| u.to_ascii_lowercase())
}

async fn read(conn: &Connection, path: &str, iface: &str) -> zbus::Result<Vec<u8>> {
    let opts: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
    let reply = conn.call_method(Some("org.bluez"), path, Some(iface), "ReadValue", &(opts,)).await?;
    reply.body().deserialize()
}

/// Сплит ли это: два Battery Level, у одного описание «Peripheral 0».
/// Характеристики появляются, только когда BlueZ дочитал сервисы
/// (ServicesResolved), до этого — None, и менеджер спросит ещё раз
pub async fn probe(conn: &Connection, info: &DevInfo) -> Option<Halves> {
    let reply = conn
        .call_method(Some("org.bluez"), "/", Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &())
        .await
        .ok()?;
    let objects: Objects = reply.body().deserialize().ok()?;
    let prefix = format!("{}/", info.path);

    let mut central = None;
    let mut peripheral = None;
    for (path, ifaces) in &objects {
        let path = path.as_str();
        if !path.starts_with(&prefix) || ifaces.get(CHAR_IFACE).and_then(uuid).as_deref() != Some(BATTERY_LEVEL) {
            continue;
        }
        let desc = objects.iter().find(|(p, i)| {
            p.as_str().strip_prefix(path).is_some_and(|rest| rest.starts_with("/desc"))
                && i.get(DESC_IFACE).and_then(uuid).as_deref() == Some(USER_DESCRIPTION)
        });
        match desc {
            None => central = Some(path.to_string()),
            Some((p, _)) => {
                let text = read(conn, p.as_str(), DESC_IFACE).await.ok()?;
                if String::from_utf8_lossy(&text) == "Peripheral 0" {
                    peripheral = Some(path.to_string());
                }
            }
        }
    }
    Some(Halves { central: central?, peripheral: peripheral? })
}

pub struct Split {
    pub info: DevInfo,
    pub halves: Halves,
    pub conn: Connection,
    pub rx: mpsc::UnboundedReceiver<DevCmd>,
    pub mgr: mpsc::UnboundedSender<(String, ToMgr)>,
}

impl Split {
    fn notify(&self, method: &'static str, params: Value) {
        let _ = self.mgr.send((self.info.mac.clone(), ToMgr::Notify { method, params }));
    }

    fn reply(&self, rpc: Value, result: Result<Value, RpcError>) {
        let _ = self.mgr.send((self.info.mac.clone(), ToMgr::Reply { rpc, result }));
    }

    fn caps(&self) -> Value {
        json!({ "model": self.info.name, "kind": "keyboard", "battery": ["left", "right"], "controls": [] })
    }

    /// Снимок, как у наушников: половина, чей заряд не прочитался, — null.
    /// Заряжается ли, ZMK не говорит
    fn battery(&self, levels: &[Option<u8>; 2]) {
        let half = |l: Option<u8>| l.map_or(Value::Null, |l| json!({ "level": l, "charging": false }));
        self.notify("battery", json!({ "left": half(levels[0]), "right": half(levels[1]) }));
    }

    async fn level(&self, path: &str) -> Option<u8> {
        read(&self.conn, path, CHAR_IFACE).await.ok()?.first().copied()
    }

    async fn read_all(&self) -> [Option<u8>; 2] {
        [self.level(&self.halves.central).await, self.level(&self.halves.peripheral).await]
    }

    pub async fn run(mut self) {
        self.notify("device", json!({ "name": self.info.name, "status": "ready", "message": null, "caps": self.caps() }));

        // Подписка до чтения: иначе изменение между ними потеряется
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender("org.bluez")
            .and_then(|b| b.interface("org.freedesktop.DBus.Properties"))
            .and_then(|b| b.member("PropertiesChanged"))
            .and_then(|b| b.path_namespace(self.info.path.as_str()))
            .map(|b| b.build());
        let mut changes = match rule {
            Ok(rule) => MessageStream::for_match_rule(rule, &self.conn, Some(16)).await.ok(),
            Err(_) => None,
        };
        for path in [&self.halves.central, &self.halves.peripheral] {
            // Уже подписаны (bluetoothd на свой BAS, прошлый запуск) — не беда
            let _ = self.conn.call_method(Some("org.bluez"), path.as_str(), Some(CHAR_IFACE), "StartNotify", &()).await;
        }

        let mut levels = self.read_all().await;
        self.battery(&levels);

        loop {
            tokio::select! {
                msg = async { changes.as_mut()?.next().await }, if changes.is_some() => {
                    let Some(Ok(msg)) = msg else {
                        changes = None;
                        continue;
                    };
                    let Some(path) = msg.header().path().map(|p| p.to_string()) else { continue };
                    let Ok((iface, changed, _)) = msg.body().deserialize::<(String, Props, Vec<String>)>() else { continue };
                    if iface != CHAR_IFACE {
                        continue;
                    }
                    let half = if path == self.halves.central { 0 } else if path == self.halves.peripheral { 1 } else { continue };
                    let level = changed.get("Value").and_then(|v| Vec::<u8>::try_from(v.clone()).ok());
                    if let Some(&l) = level.as_ref().and_then(|v| v.first()) {
                        levels[half] = Some(l);
                        self.battery(&levels);
                    }
                }
                cmd = self.rx.recv() => {
                    match cmd {
                        None => return,
                        Some(DevCmd::Act { name, rpc, .. }) if name == "refresh" => {
                            levels = self.read_all().await;
                            self.battery(&levels);
                            self.reply(rpc, Ok(Value::Null));
                        }
                        Some(DevCmd::Set { rpc, .. } | DevCmd::Act { rpc, .. }) => {
                            self.reply(rpc, Err(RpcError::new(rpc::INVALID_PARAMS, "у клавиатуры нет настроек")));
                        }
                    }
                }
            }
        }
    }
}
