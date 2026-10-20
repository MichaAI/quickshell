// Nothing и CMF by Nothing: Ear, Buds, Headphone.
//
// Протокол разобран в Gadgetbridge, ear-web (radiance-project) и BudsLink
// (maniacx). Кадр:
//   55 60 01 | команда u16 LE | длина u16 LE | seq | данные | CRC-16 LE
// CRC — CRC-16/MODBUS по всему, что до него. Запросы — 0xC0xx, ответы на
// них — 0x40xx, установки — 0xF0xx, сами по себе приходят 0xE0xx (и
// 0x60xx/0x70xx на некоторых прошивках).

use std::collections::HashMap;
use std::time::Duration;

use serde_json::{json, Value};

use super::{Check, Driver, Job, Out, Plan};

pub const UUID: &str = "aeac4a03-dff5-498f-843a-34487cf133eb";

// ===== Команды =====
const BATTERY_GET: u16 = 0xC007;
const BATTERY_RET: u16 = 0x4007;
const BATTERY_NTFY: u16 = 0xE001;
const FIRMWARE_GET: u16 = 0xC042;
const FIRMWARE_RET: u16 = 0x4042;
const MODEL_GET: u16 = 0xC01C;
const MODEL_RET: u16 = 0x401C;
const UTC_SET: u16 = 0xF00A;
const ANC_GET: u16 = 0xC01E;
const ANC_RET: u16 = 0x401E;
const ANC_NTFY: u16 = 0xE003;
const ANC_NTFY2: u16 = 0x6003;
const ANC_SET: u16 = 0xF00F;
const EQ_GET: u16 = 0xC01F;
const EQ_RET: u16 = 0x401F;
const EQ_SET: u16 = 0xF010;
const LISTEN_GET: u16 = 0xC050;
const LISTEN_RET: u16 = 0x4050;
const LISTEN_SET: u16 = 0xF01D;
const CUSTOM_EQ_GET: u16 = 0xC044;
const CUSTOM_EQ_RET: u16 = 0x4044;
const CUSTOM_EQ_SET: u16 = 0xF041;
const BASS_GET: u16 = 0xC04E;
const BASS_RET: u16 = 0x404E;
const BASS_NTFY: u16 = 0x7051;
const BASS_SET: u16 = 0xF051;
const SPATIAL_GET: u16 = 0xC04F;
const SPATIAL_RET: u16 = 0x404F;
const SPATIAL_SET: u16 = 0xF052;
const PERSONAL_GET: u16 = 0xC05A;
const PERSONAL_RET: u16 = 0x405A;
const PERSONAL_NTFY: u16 = 0xE019;
const PERSONAL_NTFY2: u16 = 0x6019;
const PERSONAL_SET: u16 = 0xF05C;
const IN_EAR_GET: u16 = 0xC00E;
const IN_EAR_RET: u16 = 0x400E;
const IN_EAR_SET: u16 = 0xF004;
const LATENCY_GET: u16 = 0xC041;
const LATENCY_RET: u16 = 0x4041;
const LATENCY_NTFY: u16 = 0x7040;
const LATENCY_SET: u16 = 0xF040;
const CODEC_GET: u16 = 0xC029;
const CODEC_RET: u16 = 0x4029;
const CODEC_SET: u16 = 0xF01C;
const DUAL_GET: u16 = 0xC027;
const DUAL_RET: u16 = 0x4027;
const DUAL_NTFY: u16 = 0xE006;
const DUAL_SET: u16 = 0xF01A;
const DUAL_LIST_GET: u16 = 0xC028;
const DUAL_LIST_RET: u16 = 0x4028;
const DUAL_EVENT: u16 = 0xE00E;
const DUAL_CONNECT_SET: u16 = 0xF01B;
const GESTURES_GET: u16 = 0xC018;
const GESTURES_RET: u16 = 0x4018;
const GESTURE_SET: u16 = 0xF003;
const RING_SET: u16 = 0xF002;
const FIT_SET: u16 = 0xF014;
const FIT_NTFY: u16 = 0xE00D;

// ===== Модели =====

struct Anc {
    off: u8,
    transparency: Option<u8>,
    /// Шумодав: один байт или уровни (тогда отдельный выбор силы)
    levels: &'static [(&'static str, u8)],
}

const ANC_FULL: Anc = Anc {
    off: 0x05,
    transparency: Some(0x07),
    levels: &[("low", 0x03), ("mid", 0x02), ("high", 0x01), ("adaptive", 0x04)],
};
const ANC_SIMPLE: Anc = Anc { off: 0x05, transparency: Some(0x07), levels: &[("anc", 0x04)] };
const ANC_THREE: Anc = Anc {
    off: 0x05,
    transparency: Some(0x07),
    levels: &[("low", 0x03), ("mid", 0x02), ("high", 0x01)],
};

struct Eq {
    presets: &'static [(&'static str, u8)],
    /// CMF: пресеты через «режим прослушивания» (0xF01D), иначе 0xF010
    listening: bool,
}

const EQ_CMF: Eq = Eq {
    presets: &[
        ("dirac", 0x00),
        ("pop", 0x03),
        ("rock", 0x01),
        ("electronic", 0x02),
        ("vocals", 0x04),
        ("classical", 0x05),
        ("custom", 0x06),
    ],
    listening: true,
};
const EQ_CMF_NO_DIRAC: Eq = Eq {
    presets: &[
        ("pop", 0x03),
        ("rock", 0x01),
        ("electronic", 0x02),
        ("vocals", 0x04),
        ("classical", 0x05),
        ("custom", 0x06),
    ],
    listening: true,
};
const EQ_NOTHING: Eq = Eq {
    presets: &[("balanced", 0x00), ("voice", 0x01), ("treble", 0x02), ("bass", 0x03), ("custom", 0x05)],
    listening: false,
};

/// Жесты: устройства (левый 2, правый 3), кнопка, а для каждого жеста —
/// какие действия ему можно дать
struct Gestures {
    button: u8,
    slots: &'static [(&'static str, u8, &'static [&'static str])],
}

// CMF Buds 2 Plus, из ear_config_file.json ear-web (B184)
const GESTURES_CMF: Gestures = Gestures {
    button: 0x01,
    slots: &[
        ("double", 0x02, &["playPause", "back", "forward", "assistant", "none"]),
        ("triple", 0x03, &["back", "forward", "assistant", "none"]),
        ("hold", 0x07, &["noise", "assistant", "none"]),
        ("doubleHold", 0x09, &["volUp", "volDown", "assistant", "none"]),
    ],
};

struct Model {
    id: &'static str,
    /// Так кончается имя, которое наушники объявляют по Bluetooth
    name: &'static str,
    single: bool,
    anc: Option<Anc>,
    eq: Option<Eq>,
    /// Частота верхней полки своего эквалайзера; 0 — своего нет
    custom_hi: f32,
    /// Ступеней усиления баса; 0 — нет
    bass: u8,
    in_ear: bool,
    latency: bool,
    fit: bool,
    dual: bool,
    spatial: bool,
    ldac: bool,
    personal: bool,
    gestures: Option<&'static Gestures>,
}

const BASE: Model = Model {
    id: "",
    name: "",
    single: false,
    anc: None,
    eq: None,
    custom_hi: 0.0,
    bass: 0,
    in_ear: false,
    latency: true,
    fit: false,
    dual: false,
    spatial: false,
    ldac: false,
    personal: false,
    gestures: None,
};

const MODELS: &[Model] = &[
    Model {
        id: "B184",
        name: "CMF Buds 2 Plus",
        anc: Some(ANC_FULL),
        eq: Some(EQ_CMF_NO_DIRAC),
        custom_hi: 6900.0,
        bass: 5,
        in_ear: true,
        fit: true,
        dual: true,
        spatial: true,
        ldac: true,
        personal: true,
        gestures: Some(&GESTURES_CMF),
        ..BASE
    },
    Model {
        id: "B179",
        name: "CMF Buds 2",
        anc: Some(ANC_FULL),
        eq: Some(EQ_CMF),
        custom_hi: 6900.0,
        bass: 5,
        fit: true,
        dual: true,
        spatial: true,
        ..BASE
    },
    Model {
        id: "B185",
        name: "CMF Buds 2a",
        anc: Some(ANC_SIMPLE),
        eq: Some(EQ_CMF),
        custom_hi: 6900.0,
        bass: 5,
        dual: true,
        ..BASE
    },
    Model {
        id: "B172",
        name: "CMF Buds Pro 2",
        anc: Some(ANC_FULL),
        eq: Some(EQ_CMF),
        custom_hi: 6900.0,
        bass: 5,
        in_ear: true,
        fit: true,
        dual: true,
        spatial: true,
        ldac: true,
        ..BASE
    },
    Model {
        id: "B168",
        name: "CMF Buds",
        anc: Some(ANC_SIMPLE),
        eq: Some(EQ_CMF),
        custom_hi: 6900.0,
        bass: 5,
        in_ear: true,
        dual: true,
        ..BASE
    },
    Model {
        id: "B193",
        name: "CMF Buds Neo",
        anc: Some(ANC_SIMPLE),
        eq: Some(EQ_CMF),
        custom_hi: 6900.0,
        bass: 5,
        dual: true,
        spatial: true,
        ..BASE
    },
    Model {
        id: "B171",
        name: "Nothing Ear",
        anc: Some(ANC_FULL),
        eq: Some(EQ_NOTHING),
        custom_hi: 3400.0,
        bass: 5,
        in_ear: true,
        fit: true,
        dual: true,
        ldac: true,
        ..BASE
    },
    Model {
        id: "B162",
        name: "Nothing Ear (a)",
        anc: Some(ANC_FULL),
        eq: Some(EQ_NOTHING),
        custom_hi: 3400.0,
        bass: 5,
        in_ear: true,
        fit: true,
        dual: true,
        ldac: true,
        ..BASE
    },
    Model {
        id: "B173",
        name: "Nothing Ear (3)",
        anc: Some(ANC_FULL),
        eq: Some(EQ_NOTHING),
        custom_hi: 3400.0,
        in_ear: true,
        fit: true,
        dual: true,
        spatial: true,
        ldac: true,
        personal: true,
        ..BASE
    },
    Model {
        id: "B155",
        name: "Ear (2)",
        anc: Some(ANC_FULL),
        eq: Some(EQ_NOTHING),
        custom_hi: 3400.0,
        in_ear: true,
        fit: true,
        dual: true,
        ..BASE
    },
    Model {
        id: "B181",
        name: "Nothing ear (1)",
        anc: Some(Anc { off: 0x05, transparency: Some(0x07), levels: &[("low", 0x03), ("high", 0x01)] }),
        eq: Some(Eq { presets: &[("balanced", 0x00), ("voice", 0x01), ("treble", 0x02), ("bass", 0x03)], listening: false }),
        ..BASE
    },
    Model {
        id: "B174",
        name: "Nothing Ear (open)",
        eq: Some(EQ_NOTHING),
        custom_hi: 3400.0,
        dual: true,
        ..BASE
    },
    Model {
        id: "B163",
        name: "Buds Pro",
        anc: Some(ANC_THREE),
        eq: Some(EQ_NOTHING),
        custom_hi: 3400.0,
        in_ear: true,
        ..BASE
    },
    Model {
        id: "B170",
        name: "Nothing Headphone (1)",
        single: true,
        anc: Some(ANC_FULL),
        eq: Some(EQ_NOTHING),
        custom_hi: 3500.0,
        bass: 5,
        in_ear: true,
        dual: true,
        ldac: true,
        ..BASE
    },
];

// Наушники Nothing, которых нет в списке: только батарея и шумодав
const GENERIC: Model = Model { id: "?", name: "Nothing", anc: Some(ANC_SIMPLE), latency: false, ..BASE };

fn label(id: &str) -> &'static str {
    match id {
        "off" => "Выкл",
        "transparency" => "Прозрачность",
        "anc" => "Шумодав",
        "low" => "Лёгкий",
        "mid" => "Средний",
        "high" => "Сильный",
        "adaptive" => "Адаптивный",
        "dirac" => "Dirac",
        "pop" => "Поп",
        "rock" => "Рок",
        "electronic" => "Электроника",
        "vocals" => "Вокал",
        "classical" => "Классика",
        "custom" => "Свой",
        "balanced" => "Баланс",
        "voice" => "Голос",
        "treble" => "Больше верхов",
        "bass" => "Больше баса",
        "playPause" => "Пауза / играть",
        "back" => "Предыдущий трек",
        "forward" => "Следующий трек",
        "assistant" => "Голосовой ассистент",
        "volUp" => "Громче",
        "volDown" => "Тише",
        "noise" => "Режимы шумоподавления",
        "none" => "Ничего",
        "double" => "Двойное касание",
        "triple" => "Тройное касание",
        "hold" => "Касание и удержание",
        "doubleHold" => "Двойное касание и удержание",
        _ => "?",
    }
}

fn gesture_action(id: &str) -> u8 {
    match id {
        "none" => 0x01,
        "playPause" => 0x02,
        "back" => 0x08,
        "forward" => 0x09,
        "noise" => 0x0A,
        "assistant" => 0x0B,
        "volUp" => 0x12,
        "volDown" => 0x13,
        _ => 0x01,
    }
}

/// Какие режимы шума перебирает жест: 0x0A — все три, 0x14..0x16 — пары
fn noise_cycle(action: u8) -> Option<&'static [&'static str]> {
    match action {
        0x0A => Some(&["transparency", "anc", "off"]),
        0x14 => Some(&["anc", "off"]),
        0x15 => Some(&["transparency", "off"]),
        0x16 => Some(&["transparency", "anc"]),
        _ => None,
    }
}

fn noise_action(cycle: &[String]) -> u8 {
    let has = |m: &str| cycle.iter().any(|c| c == m);
    match (has("transparency"), has("anc"), has("off")) {
        (false, true, true) => 0x14,
        (true, false, true) => 0x15,
        (true, true, false) => 0x16,
        _ => 0x0A,
    }
}

fn options(ids: impl IntoIterator<Item = &'static str>) -> Value {
    ids.into_iter().map(|id| json!({ "id": id, "label": label(id) })).collect()
}

// ===== Кадры =====

pub fn crc16(data: &[u8]) -> u16 {
    let mut crc: u16 = 0xFFFF;
    for &b in data {
        crc ^= b as u16;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xA001 } else { crc >> 1 };
        }
    }
    crc
}

pub fn encode(cmd: u16, seq: u8, payload: &[u8]) -> Vec<u8> {
    let mut p = vec![0x55, 0x60, 0x01, cmd as u8, (cmd >> 8) as u8, payload.len() as u8, 0x00, seq];
    p.extend_from_slice(payload);
    let crc = crc16(&p);
    p.extend_from_slice(&[crc as u8, (crc >> 8) as u8]);
    p
}

/// Вынуть из буфера целые кадры: (команда, данные)
pub fn decode(buf: &mut Vec<u8>) -> Vec<(u16, Vec<u8>)> {
    let mut out = Vec::new();
    loop {
        let Some(start) = buf.iter().position(|&b| b == 0x55) else {
            buf.clear();
            break;
        };
        buf.drain(..start);
        if buf.len() < 8 {
            break;
        }
        let control = u16::from_le_bytes([buf[1], buf[2]]);
        let len = u16::from_le_bytes([buf[5], buf[6]]) as usize;
        let total = 8 + len + if control & 0x20 != 0 { 2 } else { 0 };
        if buf.len() < total {
            break;
        }
        let cmd = u16::from_le_bytes([buf[3], buf[4]]);
        out.push((cmd, buf[8..8 + len].to_vec()));
        buf.drain(..total);
    }
    out
}

/// Гейн эквалайзера: float LE, но крошечные отрицательные шлют как
/// 00 00 00 8x поверх положительного (повторяем ear-web)
fn decode_gain(b: &[u8]) -> f32 {
    let [b0, b1, b2, b3] = [b[0], b[1], b[2], b[3]];
    if b3 == 0 && b2 == 0 && b1 == 0 && b0 & 0x80 != 0 {
        return -f32::from_le_bytes([b0 & 0x7F, 0, 0, 0]);
    }
    f32::from_le_bytes([b0, b1, b2, b3])
}

/// Свой эквалайзер [бас, середина, верх] → данные 0xF041. Полосы идут
/// пиком (середина), верхней полкой и нижней полкой, как у Nothing X
pub fn custom_eq_packet(bands: [f32; 3], hi: f32) -> Vec<u8> {
    let [bass, mid, treble] = bands;
    let filters: [(u8, f32, f32, f32); 3] = [(1, mid, 980.0, 0.7), (2, treble, hi, 1.0), (0, bass, 140.0, 0.8)];
    let max = bands.iter().fold(0.0f32, |m, &g| m.max(g));
    let mut p = vec![3u8];
    p.extend_from_slice(&(-max).to_le_bytes());
    for (kind, gain, freq, q) in filters {
        p.push(kind);
        p.extend_from_slice(&gain.to_le_bytes());
        p.extend_from_slice(&freq.to_le_bytes());
        p.extend_from_slice(&q.to_le_bytes());
    }
    p.extend_from_slice(&[0; 9]);
    p
}

fn mac_hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02X}")).collect::<Vec<_>>().join(":")
}

// ===== Драйвер =====

pub struct Nothing {
    model: &'static Model,
    seq: u8,
    rx: Vec<u8>,
    values: HashMap<String, Value>,
    /// Последняя сила шумодава — её включаем, когда выбирают «Шумодав»
    anc_level: u8,
    bass_on: bool,
    bass_level: u8,
    bands: [f32; 3],
    devices: Vec<Value>,
    list_pages: u8,
    fit: Value,
}

pub fn probe(name: &str, uuids: &[String]) -> Option<Nothing> {
    let model = MODELS.iter().find(|m| name.ends_with(m.name));
    if model.is_none() && !uuids.iter().any(|u| u == UUID) {
        return None;
    }
    Some(Nothing {
        model: model.unwrap_or(&GENERIC),
        seq: 0,
        rx: Vec::new(),
        values: HashMap::new(),
        anc_level: 0,
        bass_on: false,
        bass_level: 3,
        bands: [0.0; 3],
        devices: Vec::new(),
        list_pages: 0,
        fit: Value::Null,
    })
}

impl Nothing {
    fn job(&mut self, cmd: u16, payload: &[u8]) -> Job {
        self.seq = if self.seq >= 250 { 1 } else { self.seq + 1 };
        Job { frame: encode(cmd, self.seq, payload), wait: &[], timeout: Job::WAIT }
    }

    /// Запрос, после которого ждём ответ
    fn ask(&mut self, cmd: u16, wait: &'static [u16]) -> Job {
        Job { wait, ..self.job(cmd, &[]) }
    }

    fn put(&mut self, out: &mut Vec<Out>, id: &str, v: Value) {
        self.values.insert(id.to_string(), v.clone());
        out.push(Out::Notify("value", json!({ "id": id, "value": v })));
    }

    fn eq_cmds(&self) -> Option<(u16, u16, &'static [u16])> {
        let eq = self.model.eq.as_ref()?;
        Some(if eq.listening {
            (LISTEN_GET, LISTEN_SET, &[LISTEN_RET])
        } else {
            (EQ_GET, EQ_SET, &[EQ_RET])
        })
    }

    fn request_all(&mut self) -> Vec<Job> {
        let m = self.model;
        let mut jobs = vec![self.ask(BATTERY_GET, &[BATTERY_RET]), self.ask(FIRMWARE_GET, &[FIRMWARE_RET])];
        if m.id != "B181" {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as u32)
                .unwrap_or(0);
            jobs.push(self.job(UTC_SET, &now.to_be_bytes()));
        }
        if m.anc.is_some() {
            jobs.push(self.ask(ANC_GET, &[ANC_RET]));
        }
        if let Some((get, _, ret)) = self.eq_cmds() {
            jobs.push(self.ask(get, ret));
        }
        if m.custom_hi > 0.0 {
            jobs.push(self.ask(CUSTOM_EQ_GET, &[CUSTOM_EQ_RET]));
        }
        if m.bass > 0 {
            jobs.push(self.ask(BASS_GET, &[BASS_RET]));
        }
        if m.spatial {
            jobs.push(self.ask(SPATIAL_GET, &[SPATIAL_RET]));
        }
        if m.personal {
            jobs.push(self.ask(PERSONAL_GET, &[PERSONAL_RET]));
        }
        if m.in_ear {
            jobs.push(self.ask(IN_EAR_GET, &[IN_EAR_RET]));
        }
        if m.latency {
            jobs.push(self.ask(LATENCY_GET, &[LATENCY_RET]));
        }
        if m.ldac {
            jobs.push(self.ask(CODEC_GET, &[CODEC_RET]));
        }
        if m.gestures.is_some() {
            jobs.push(self.ask(GESTURES_GET, &[GESTURES_RET]));
        }
        if m.dual {
            jobs.push(self.ask(DUAL_GET, &[DUAL_RET]));
            jobs.push(self.request_devices(true));
        }
        jobs
    }

    fn request_devices(&mut self, fresh: bool) -> Job {
        if fresh {
            self.devices.clear();
            self.list_pages = 0;
        }
        self.list_pages += 1;
        let have = self.devices.len() as u8;
        Job { wait: &[DUAL_LIST_RET], ..self.job(DUAL_LIST_GET, &[have]) }
    }

    fn battery(&self, p: &[u8], out: &mut Vec<Out>) {
        let Some(&count) = p.first() else { return };
        let mut b = serde_json::Map::new();
        for i in 0..count as usize {
            let Some(pair) = p.get(1 + i * 2..3 + i * 2) else { break };
            let key = match pair[0] {
                0x02 => "left",
                0x03 => "right",
                0x04 => "case",
                0x06 => "single",
                _ => continue,
            };
            b.insert(key.into(), json!({ "level": pair[1] & 0x7F, "charging": pair[1] & 0x80 != 0 }));
        }
        out.push(Out::Notify("battery", Value::Object(b)));
    }

    fn anc(&mut self, mode: u8, out: &mut Vec<Out>) {
        let Some(anc) = &self.model.anc else { return };
        if mode == anc.off {
            self.put(out, "noise", json!("off"));
        } else if Some(mode) == anc.transparency {
            self.put(out, "noise", json!("transparency"));
        } else if let Some((id, _)) = anc.levels.iter().find(|(_, b)| *b == mode) {
            self.anc_level = mode;
            self.put(out, "noise", json!("anc"));
            if anc.levels.len() > 1 {
                self.put(out, "ancLevel", json!(id));
            }
        }
    }

    fn gestures(&mut self, p: &[u8], out: &mut Vec<Out>) {
        let Some(g) = self.model.gestures else { return };
        let Some(&count) = p.first() else { return };
        for i in 0..count as usize {
            let Some(s) = p.get(1 + i * 4..5 + i * 4) else { break };
            let side = match s[0] {
                0x02 => "left",
                0x03 => "right",
                _ => continue,
            };
            let Some((gid, _, allowed)) = g.slots.iter().find(|(_, t, _)| *t == s[2]) else { continue };
            let v = gesture_value(allowed, s[3]);
            self.put(out, &format!("gesture.{side}.{gid}"), v);
        }
    }

    fn device_list(&mut self, p: &[u8], out: &mut Vec<Out>) {
        let Some(&count) = p.get(2) else { return };
        let mut off = 3;
        let mut added = false;
        for _ in 0..count {
            let Some(head) = p.get(off..off + 8) else { break };
            let flags = head[0];
            let mac = mac_hex(&head[1..7]);
            let clipped = head[7] & 0x80 != 0;
            let len = (head[7] & 0x7F) as usize;
            let Some(name) = p.get(off + 8..off + 8 + len) else { break };
            let mut name = String::from_utf8_lossy(name).replace('\u{FFFD}', "");
            if clipped {
                name.push('…');
            }
            off += 8 + len;
            let dev = json!({
                "mac": mac,
                "name": name,
                "connected": flags & 0x0F != 0,
                "self": flags & 0xF0 != 0,
            });
            match self.devices.iter_mut().find(|d| d["mac"] == mac) {
                Some(d) => *d = dev,
                None => {
                    self.devices.push(dev);
                    added = true;
                }
            }
        }
        out.push(Out::Notify("devices", json!({ "list": self.devices })));
        // Список приходит страницами: просим следующую, пока прибавляется
        if added && self.list_pages < 20 {
            let job = self.request_devices(false);
            out.push(Out::Job(job));
        }
    }

    fn device_event(&mut self, p: &[u8], out: &mut Vec<Out>) {
        if p.len() < 7 {
            return;
        }
        let mac = mac_hex(&p[1..7]);
        match self.devices.iter_mut().find(|d| d["mac"] == mac) {
            Some(d) if p.get(7).copied().unwrap_or(0) != 1 => {
                d["connected"] = json!(p[0] == 1);
                out.push(Out::Notify("devices", json!({ "list": self.devices })));
            }
            _ => {
                let job = self.request_devices(true);
                out.push(Out::Job(job));
            }
        }
    }

    /// Установка + запрос, ответ на который подтвердит значение
    fn confirm(&mut self, set: u16, payload: &[u8], get: u16, ret: &'static [u16], id: &str, want: Value) -> Plan {
        let jobs = vec![self.job(set, payload), self.ask(get, ret)];
        Plan { jobs, check: Check::Value(id.to_string(), want) }
    }
}

fn gesture_value(allowed: &[&str], code: u8) -> Value {
    match noise_cycle(code) {
        Some(cycle) => json!({ "action": "noise", "cycle": cycle }),
        None => {
            let action = allowed.iter().find(|a| gesture_action(a) == code).copied().unwrap_or("none");
            json!({ "action": action })
        }
    }
}

impl Driver for Nothing {
    fn uuid(&self) -> &'static str {
        UUID
    }

    fn value(&self, id: &str) -> Option<Value> {
        self.values.get(id).cloned()
    }

    fn fit(&self) -> Value {
        self.fit.clone()
    }

    fn start(&mut self) -> Vec<Job> {
        let mut jobs = Vec::new();
        if std::ptr::eq(self.model, &GENERIC) {
            jobs.push(self.ask(MODEL_GET, &[MODEL_RET]));
        }
        jobs.extend(self.request_all());
        jobs
    }

    fn feed(&mut self, data: &[u8]) -> Vec<(u16, Vec<u8>)> {
        self.rx.extend_from_slice(data);
        if self.rx.len() > 4096 {
            self.rx.clear();
        }
        decode(&mut self.rx)
    }

    fn handle(&mut self, cmd: u16, p: &[u8]) -> Vec<Out> {
        let mut out = Vec::new();
        let b = |i: usize| p.get(i).copied().unwrap_or(0);
        match cmd {
            BATTERY_RET | BATTERY_NTFY => self.battery(p, &mut out),
            ANC_RET | ANC_NTFY | ANC_NTFY2 => self.anc(b(1), &mut out),
            FIRMWARE_RET => out.push(Out::Notify("info", json!({ "firmware": String::from_utf8_lossy(p) }))),
            MODEL_RET => {
                let id = format!("{:X}", u16::from_le_bytes([b(0), b(1)]));
                if let Some(m) = MODELS.iter().find(|m| m.id == id) {
                    if !std::ptr::eq(m, self.model) {
                        self.model = m;
                        out.push(Out::Caps);
                        out.extend(self.request_all().into_iter().map(Out::Job));
                    }
                }
            }
            EQ_RET | LISTEN_RET => {
                let preset = self.model.eq.as_ref().and_then(|eq| eq.presets.iter().find(|(_, v)| *v == b(0)));
                if let Some((id, _)) = preset {
                    self.put(&mut out, "eq", json!(id));
                }
            }
            CUSTOM_EQ_RET => {
                let gain = |i: usize| p.get(6 + i * 13..10 + i * 13).map(decode_gain);
                if let (Some(mid), Some(treble), Some(bass)) = (gain(0), gain(1), gain(2)) {
                    self.bands = [bass, mid, treble].map(|g| g.clamp(-6.0, 6.0).round());
                    let bands = self.bands;
                    self.put(&mut out, "eqBands", json!(bands));
                }
            }
            BASS_RET | BASS_NTFY => {
                self.bass_on = b(0) == 1;
                if b(1) > 0 {
                    self.bass_level = (b(1) / 2).clamp(1, self.model.bass.max(1));
                }
                let (on, level) = (self.bass_on, self.bass_level);
                self.put(&mut out, "bass", json!(on));
                self.put(&mut out, "bassLevel", json!(level));
            }
            SPATIAL_RET => self.put(&mut out, "spatial", json!(b(0) != 0)),
            PERSONAL_RET | PERSONAL_NTFY | PERSONAL_NTFY2 => self.put(&mut out, "personal", json!(b(0) == 1)),
            IN_EAR_RET => self.put(&mut out, "inEar", json!(b(2) == 1)),
            LATENCY_RET | LATENCY_NTFY => self.put(&mut out, "latency", json!(b(0) == 1)),
            CODEC_RET => self.put(&mut out, "ldac", json!(b(0) == 2)),
            DUAL_RET | DUAL_NTFY => self.put(&mut out, "dual", json!(b(0) == 1)),
            DUAL_LIST_RET => self.device_list(p, &mut out),
            DUAL_EVENT => self.device_event(p, &mut out),
            GESTURES_RET => self.gestures(p, &mut out),
            FIT_NTFY => {
                let r = |v: u8| match v {
                    0 => "good",
                    1 => "bad",
                    _ => "error",
                };
                self.fit = json!({ "left": r(b(0)), "right": r(b(1)) });
            }
            _ => {}
        }
        out
    }

    fn set(&mut self, id: &str, v: &Value) -> Result<Plan, String> {
        let m = self.model;
        let bool_of = |v: &Value| v.as_bool().ok_or_else(|| format!("{id}: нужно true/false"));
        let unknown = || format!("{} не умеет {id}", m.name);
        match id {
            "noise" => {
                let anc = m.anc.as_ref().ok_or_else(unknown)?;
                let mode = match v.as_str() {
                    Some("off") => anc.off,
                    Some("transparency") => anc.transparency.ok_or("прозрачности нет")?,
                    Some("anc") if anc.levels.iter().any(|(_, b)| *b == self.anc_level) => self.anc_level,
                    // Сила ещё не известна: адаптивный, а нет его — последний
                    Some("anc") => anc.levels.iter().find(|(l, _)| *l == "adaptive").unwrap_or(anc.levels.last().unwrap()).1,
                    _ => return Err(format!("noise: нет режима {v}")),
                };
                Ok(self.confirm(ANC_SET, &[0x01, mode, 0x00], ANC_GET, &[ANC_RET], id, v.clone()))
            }
            "ancLevel" => {
                let anc = m.anc.as_ref().ok_or_else(unknown)?;
                let s = v.as_str().unwrap_or("");
                let (_, mode) = anc.levels.iter().find(|(l, _)| *l == s).ok_or(format!("ancLevel: нет силы {v}"))?;
                Ok(self.confirm(ANC_SET, &[0x01, *mode, 0x00], ANC_GET, &[ANC_RET], id, v.clone()))
            }
            "eq" => {
                let eq = m.eq.as_ref().ok_or_else(unknown)?;
                let (get, set, ret) = self.eq_cmds().unwrap();
                let s = v.as_str().unwrap_or("");
                let (_, preset) = eq.presets.iter().find(|(p, _)| *p == s).ok_or(format!("eq: нет пресета {v}"))?;
                let mut plan = self.confirm(set, &[*preset, 0x00], get, ret, id, v.clone());
                if s == "custom" && m.custom_hi > 0.0 {
                    let job = self.ask(CUSTOM_EQ_GET, &[CUSTOM_EQ_RET]);
                    plan.jobs.insert(1, job);
                }
                Ok(plan)
            }
            "eqBands" => {
                if m.custom_hi <= 0.0 {
                    return Err(unknown());
                }
                let arr = v.as_array().filter(|a| a.len() == 3).ok_or("eqBands: нужно три числа")?;
                let mut bands = [0.0f32; 3];
                for (i, x) in arr.iter().enumerate() {
                    bands[i] = (x.as_f64().ok_or("eqBands: нужно три числа")? as f32).clamp(-6.0, 6.0).round();
                }
                let packet = custom_eq_packet(bands, m.custom_hi);
                Ok(self.confirm(CUSTOM_EQ_SET, &packet, CUSTOM_EQ_GET, &[CUSTOM_EQ_RET], id, json!(bands)))
            }
            "bass" | "bassLevel" => {
                if m.bass == 0 {
                    return Err(unknown());
                }
                let (mut on, mut level) = (self.bass_on, self.bass_level);
                let want = if id == "bass" {
                    on = bool_of(v)?;
                    json!(on)
                } else {
                    level = v.as_u64().ok_or("bassLevel: нужно число")?.clamp(1, m.bass as u64) as u8;
                    json!(level)
                };
                Ok(self.confirm(BASS_SET, &[on as u8, level * 2], BASS_GET, &[BASS_RET], id, want))
            }
            "spatial" if m.spatial => {
                let on = bool_of(v)?;
                Ok(self.confirm(SPATIAL_SET, &[on as u8, 0x00], SPATIAL_GET, &[SPATIAL_RET], id, json!(on)))
            }
            "personal" if m.personal => {
                let on = bool_of(v)?;
                Ok(self.confirm(PERSONAL_SET, &[on as u8], PERSONAL_GET, &[PERSONAL_RET], id, json!(on)))
            }
            "inEar" if m.in_ear => {
                let on = bool_of(v)?;
                Ok(self.confirm(IN_EAR_SET, &[0x01, 0x01, on as u8], IN_EAR_GET, &[IN_EAR_RET], id, json!(on)))
            }
            "latency" if m.latency => {
                let on = bool_of(v)?;
                let p = [if on { 0x01 } else { 0x02 }, 0x00];
                Ok(self.confirm(LATENCY_SET, &p, LATENCY_GET, &[LATENCY_RET], id, json!(on)))
            }
            // Наушники сразу уходят в перезагрузку — подтверждать некому
            "ldac" if m.ldac => {
                let on = bool_of(v)?;
                self.values.insert(id.into(), json!(on));
                let job = self.job(CODEC_SET, &[if on { 0x02 } else { 0x00 }]);
                Ok(Plan { jobs: vec![job], check: Check::Done })
            }
            "dual" if m.dual => {
                let on = bool_of(v)?;
                let mut plan = self.confirm(DUAL_SET, &[on as u8], DUAL_GET, &[DUAL_RET], id, json!(on));
                if on {
                    let job = self.request_devices(true);
                    plan.jobs.insert(1, job);
                }
                Ok(plan)
            }
            _ if id.starts_with("gesture.") => {
                let g = m.gestures.ok_or_else(unknown)?;
                let mut parts = id.split('.').skip(1);
                let (side, gid) = (parts.next().unwrap_or(""), parts.next().unwrap_or(""));
                let dev = match side {
                    "left" => 0x02,
                    "right" => 0x03,
                    _ => return Err(format!("{id}: нет стороны {side}")),
                };
                let (_, kind, allowed) = g.slots.iter().find(|(n, _, _)| *n == gid).ok_or(format!("нет жеста {gid}"))?;
                let action = v["action"].as_str().unwrap_or("");
                if !allowed.contains(&action) {
                    return Err(format!("{gid}: нельзя {action}"));
                }
                let code = if action == "noise" {
                    let cycle: Vec<String> = v["cycle"]
                        .as_array()
                        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
                        .unwrap_or_default();
                    if cycle.len() < 2 {
                        return Err("по кругу нужно хотя бы два режима".into());
                    }
                    noise_action(&cycle)
                } else {
                    gesture_action(action)
                };
                let want = gesture_value(allowed, code);
                let p = [0x01, dev, g.button, *kind, code];
                Ok(self.confirm(GESTURE_SET, &p, GESTURES_GET, &[GESTURES_RET], id, want))
            }
            _ => Err(unknown()),
        }
    }

    fn act(&mut self, name: &str, p: &Value) -> Result<Plan, String> {
        let m = self.model;
        let jobs = match name {
            "ring" => {
                let on = p["on"].as_bool().unwrap_or(false) as u8;
                if m.id == "B181" {
                    vec![self.job(RING_SET, &[on])]
                } else {
                    let side = match p["side"].as_str() {
                        _ if m.single => 0x06,
                        Some("left") => 0x02,
                        Some("right") => 0x03,
                        _ => return Err("ring: side — left или right".into()),
                    };
                    vec![self.job(RING_SET, &[side, on])]
                }
            }
            "fitTest" if m.fit => {
                self.fit = Value::Null;
                // Тест играет звук в уши несколько секунд
                let job = Job { wait: &[FIT_NTFY], timeout: Duration::from_secs(20), ..self.job(FIT_SET, &[0x01]) };
                return Ok(Plan { jobs: vec![job], check: Check::Fit });
            }
            "dualConnect" if m.dual => {
                let mac = p["mac"].as_str().ok_or("dualConnect: нужен mac")?;
                let bytes: Vec<u8> = mac.split([':', '-']).filter_map(|x| u8::from_str_radix(x, 16).ok()).collect();
                if bytes.len() != 6 {
                    return Err(format!("dualConnect: кривой mac {mac}"));
                }
                let mut payload = vec![p["connect"].as_bool().unwrap_or(true) as u8];
                payload.extend(bytes);
                vec![self.job(DUAL_CONNECT_SET, &payload)]
            }
            "refresh" => self.request_all(),
            _ => return Err(format!("{} не умеет {name}", m.name)),
        };
        Ok(Plan { jobs, check: Check::Done })
    }

    fn poll(&mut self) -> Vec<Job> {
        vec![self.ask(BATTERY_GET, &[BATTERY_RET])]
    }

    fn caps(&self) -> Value {
        let m = self.model;
        let mut c: Vec<Value> = Vec::new();
        if let Some(anc) = &m.anc {
            let mut modes = vec!["off"];
            if anc.transparency.is_some() {
                modes.push("transparency");
            }
            modes.push("anc");
            let icon = |id: &str| match id {
                "off" => "󰟎",
                "transparency" => "󰈈",
                _ => "󰋎",
            };
            let opts: Vec<Value> = modes.iter().map(|id| json!({ "id": id, "label": label(id), "icon": icon(id) })).collect();
            c.push(json!({
                "id": "noise", "kind": "choice", "page": "noise", "label": "Шумоподавление",
                "options": opts,
            }));
            if anc.levels.len() > 1 {
                c.push(json!({
                    "id": "ancLevel", "kind": "choice", "page": "noise", "label": "Сила шумодава",
                    "options": options(anc.levels.iter().map(|(l, _)| *l)),
                    "showIf": { "noise": "anc" },
                }));
            }
        }
        if let Some(eq) = &m.eq {
            c.push(json!({
                "id": "eq", "kind": "choice", "style": "chips", "page": "sound", "label": "Эквалайзер",
                "options": options(eq.presets.iter().map(|(p, _)| *p)),
            }));
            if m.custom_hi > 0.0 {
                c.push(json!({
                    "id": "eqBands", "kind": "bands", "page": "sound", "label": "Свой эквалайзер",
                    "bands": ["Бас", "Середина", "Верх"], "min": -6, "max": 6,
                    "showIf": { "eq": "custom" },
                }));
            }
        }
        if m.bass > 0 {
            c.push(json!({ "id": "bass", "kind": "toggle", "page": "sound", "label": "Усиление баса", "icon": "󰓃" }));
            c.push(json!({
                "id": "bassLevel", "kind": "level", "page": "sound", "label": "Уровень баса",
                "min": 1, "max": m.bass, "showIf": { "bass": true },
            }));
        }
        if m.spatial {
            c.push(json!({ "id": "spatial", "kind": "toggle", "page": "sound", "label": "Пространственный звук", "icon": "󰦤" }));
        }
        if m.personal {
            c.push(json!({
                "id": "personal", "kind": "toggle", "page": "sound", "label": "Персональный звук", "icon": "󰋋",
                "note": "Профиль слуха настраивается в Nothing X",
            }));
        }
        if let Some(g) = m.gestures {
            c.push(json!({
                "id": "gestures", "kind": "gestures", "page": "gestures", "label": "Жесты",
                "sides": [{ "id": "left", "label": "Левый" }, { "id": "right", "label": "Правый" }],
                "gestures": g.slots.iter().map(|(id, _, allowed)| json!({
                    "id": id,
                    "label": label(id),
                    "options": allowed.iter().map(|a| {
                        let mut o = json!({ "id": a, "label": label(a) });
                        if *a == "noise" {
                            o["cycle"] = json!(true);
                            o["modes"] = options(["transparency", "anc", "off"]);
                        }
                        o
                    }).collect::<Vec<_>>(),
                })).collect::<Vec<_>>(),
            }));
        }
        if m.in_ear {
            c.push(json!({ "id": "inEar", "kind": "toggle", "page": "more", "label": "Датчик в ухе", "icon": "󰟅",
                "note": "Пауза, когда наушник вынут" }));
        }
        if m.latency {
            c.push(json!({ "id": "latency", "kind": "toggle", "page": "more", "label": "Низкая задержка", "icon": "󰊴" }));
        }
        if m.ldac {
            c.push(json!({ "id": "ldac", "kind": "toggle", "page": "more", "label": "LDAC", "icon": "󰎈",
                "note": "Наушники перезагрузятся" }));
        }
        if m.dual {
            c.push(json!({ "id": "dual", "kind": "toggle", "page": "more", "label": "Два устройства сразу", "icon": "󰓃" }));
            c.push(json!({ "id": "dualDevices", "kind": "devices", "page": "more", "label": "Устройства наушников",
                "showIf": { "dual": true } }));
        }
        let sides = if m.single {
            json!([{ "id": "single", "label": "Найти" }])
        } else {
            json!([{ "id": "left", "label": "Левый" }, { "id": "right", "label": "Правый" }])
        };
        c.push(json!({ "id": "ring", "kind": "ring", "page": "more", "label": "Найти наушники", "sides": sides }));
        if m.fit {
            c.push(json!({ "id": "fitTest", "kind": "fitTest", "page": "more", "label": "Тест посадки" }));
        }
        let battery: &[&str] = if m.single { &["single"] } else { &["left", "right", "case"] };
        json!({
            "driver": "nothing",
            "model": if std::ptr::eq(m, &GENERIC) { "Nothing" } else { m.name },
            "battery": battery,
            "controls": c,
        })
    }

}

#[cfg(test)]
mod tests {
    use super::*;

    // Эталоны в тестах посчитаны JS-кодом ear-web (send, crc16,
    // createEQPacket) — тем, что проверен на живых наушниках

    #[test]
    fn frame_matches_ear_web() {
        assert_eq!(encode(BATTERY_GET, 1, &[]), vec![0x55, 0x60, 0x01, 0x07, 0xC0, 0x00, 0x00, 0x01, 0xAC, 0xDF]);
    }

    #[test]
    fn crc_is_modbus() {
        // CRC-16/MODBUS("123456789") = 0x4B37
        assert_eq!(crc16(b"123456789"), 0x4B37);
    }

    #[test]
    fn decode_splits_and_skips_garbage() {
        let mut buf = vec![0x00, 0x13];
        buf.extend(encode(ANC_RET, 3, &[0x01, 0x04, 0x00]));
        buf.extend(&encode(BATTERY_NTFY, 4, &[0x01, 0x02, 0xD0])[..5]);
        let frames = decode(&mut buf);
        assert_eq!(frames, vec![(ANC_RET, vec![0x01, 0x04, 0x00])]);
        assert_eq!(buf.len(), 5); // половинка кадра ждёт продолжения
    }

    #[test]
    fn custom_eq_flat_matches_ear_web() {
        let p = custom_eq_packet([0.0; 3], 6900.0);
        let want: [u8; 53] = [
            0x03, 0x00, 0x00, 0x00, 0x80, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x75, 0x44, 0x33, 0x33, 0x33,
            0x3f, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xa0, 0xd7, 0x45, 0x00, 0x00, 0x80, 0x3f, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x0c, 0x43, 0xcd, 0xcc, 0x4c, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00,
        ];
        assert_eq!(p, want);
    }

    #[test]
    fn custom_eq_matches_ear_web() {
        let want: [u8; 53] = [
            0x03, 0x00, 0x00, 0xa0, 0xc0, 0x01, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x75, 0x44, 0x33, 0x33, 0x33,
            0x3f, 0x02, 0x00, 0x00, 0xa0, 0x40, 0x00, 0xa0, 0xd7, 0x45, 0x00, 0x00, 0x80, 0x3f, 0x00, 0x00, 0x00,
            0x40, 0xc0, 0x00, 0x00, 0x0c, 0x43, 0xcd, 0xcc, 0x4c, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00,
        ];
        assert_eq!(custom_eq_packet([-3.0, 2.0, 5.0], 6900.0), want);
    }

    #[test]
    fn custom_eq_roundtrip() {
        let p = custom_eq_packet([-3.0, 2.0, 5.0], 6900.0);
        let gain = |i: usize| decode_gain(&p[6 + i * 13..10 + i * 13]);
        assert_eq!([gain(2), gain(0), gain(1)], [-3.0, 2.0, 5.0]);
        assert_eq!(f32::from_le_bytes(p[1..5].try_into().unwrap()), -5.0);
    }

    #[test]
    fn gesture_noise_codes() {
        let c = |v: &[&str]| noise_action(&v.iter().map(|s| s.to_string()).collect::<Vec<_>>());
        assert_eq!(c(&["transparency", "anc"]), 0x16);
        assert_eq!(c(&["anc", "off"]), 0x14);
        assert_eq!(c(&["transparency", "off"]), 0x15);
        assert_eq!(c(&["transparency", "anc", "off"]), 0x0A);
    }

    #[test]
    fn models_by_name() {
        let m = |n: &str| probe(n, &[]).map(|d| d.model.id);
        assert_eq!(m("CMF Buds 2 Plus"), Some("B184"));
        assert_eq!(m("CMF Buds 2"), Some("B179"));
        assert_eq!(m("CMF Buds 2a"), Some("B185"));
        assert_eq!(m("Nothing Ear (a)"), Some("B162"));
        assert_eq!(m("JBL Tune"), None);
        assert_eq!(probe("Странные уши", &[UUID.to_string()]).map(|d| d.model.id), Some("?"));
    }
}
