// Драйверы наушников. Драйвер не трогает ни сокет, ни таймеры: он
// собирает кадры (Job) и разбирает пришедшие, а ждать ответы, держать
// темп и отвечать шеллу — дело device.rs.
//
// Наружу все драйверы отдают одинаковое описание контролов — попаут рисует
// его как есть, ничего не зная о модели:
//
//   {"id", "kind", "page", "label", "icon"?, "showIf"?: {"<id>": значение}}
//   kind:
//     choice   — один из options [{"id", "label", "icon"?}]; style: "chips" —
//                чипами в несколько строк, иначе группой кнопок
//     toggle   — да/нет; note — пояснение под строкой
//     level    — целое от min до max
//     bands    — эквалайзер: bands [подписи], значения min..max (дБ)
//     gestures — sides [{"id", "label"}], gestures [{"id", "label", "options"}];
//                значение "gesture.<side>.<gesture>" — {"action", "cycle"?}:
//                у действия с "cycle": true выбираются режимы шума по кругу
//     devices  — к чему подключены сами наушники (уведомление devices)
//     ring     — «найти наушники», sides [{"id", "label"}]
//     fitTest  — тест посадки, результат — ответ на fitTest
//   page — вкладка попаута: noise, sound, gestures, more
//
// Новые наушники: файл с типом, реализующим Driver, и строчка в pick()
// (и в uuids(), если у них свой UUID).

pub mod nothing;

use std::time::Duration;

use serde_json::Value;

/// Кадр в наушники. Если wait не пуст — следующий не шлём, пока не придёт
/// кадр одной из этих команд (или не выйдет timeout)
pub struct Job {
    pub frame: Vec<u8>,
    pub wait: &'static [u16],
    pub timeout: Duration,
}

impl Job {
    pub const WAIT: Duration = Duration::from_millis(1500);
}

/// Что делать с ответом шеллу, когда последний кадр плана отработал
pub enum Check {
    /// Сверить значение контрола с запрошенным (каноничным)
    Value(String, Value),
    /// Вернуть результат теста посадки
    Fit,
    /// Просто «готово»
    Done,
}

pub struct Plan {
    pub jobs: Vec<Job>,
    pub check: Check,
}

pub enum Out {
    /// Уведомление шеллу: метод и параметры (device добавит device.rs)
    Notify(&'static str, Value),
    /// Ещё кадр (следующая страница списка и т. п.)
    Job(Job),
    /// Модель уточнилась — caps другие
    Caps,
}

pub trait Driver: Send + Sync {
    /// UUID RFCOMM-канала управления
    fn uuid(&self) -> &'static str;
    /// Модель и контролы
    fn caps(&self) -> Value;
    /// Текущее значение контрола, если уже известно
    fn value(&self, id: &str) -> Option<Value>;
    /// Последний результат теста посадки
    fn fit(&self) -> Value;
    /// Канал открыт: что запросить
    fn start(&mut self) -> Vec<Job>;
    /// Байты из канала (кусками, как придётся) → целые кадры
    fn feed(&mut self, data: &[u8]) -> Vec<(u16, Vec<u8>)>;
    /// Разобрать кадр
    fn handle(&mut self, cmd: u16, payload: &[u8]) -> Vec<Out>;
    /// Поменять контрол
    fn set(&mut self, id: &str, value: &Value) -> Result<Plan, String>;
    /// Действие: ring, fitTest, dualConnect, refresh
    fn act(&mut self, name: &str, params: &Value) -> Result<Plan, String>;
    /// Раз в минуту: опросить то, что само не приходит
    fn poll(&mut self) -> Vec<Job> {
        Vec::new()
    }
}

pub fn uuids() -> Vec<&'static str> {
    vec![nothing::UUID]
}

pub fn pick(name: &str, uuids: &[String]) -> Option<Box<dyn Driver>> {
    nothing::probe(name, uuids).map(|d| Box::new(d) as Box<dyn Driver>)
}
