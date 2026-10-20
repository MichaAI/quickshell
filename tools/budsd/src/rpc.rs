// JSON-RPC 2.0 поверх stdin/stdout, по сообщению на строку.

use serde_json::{json, Value};

pub const PARSE_ERROR: i64 = -32700;
pub const INVALID_REQUEST: i64 = -32600;
pub const METHOD_NOT_FOUND: i64 = -32601;
pub const INVALID_PARAMS: i64 = -32602;
/// Таких наушников нет (не подключены или не поддерживаются)
pub const NO_DEVICE: i64 = 1;
/// Нет канала к наушникам
pub const NO_LINK: i64 = 2;
/// Наушники не ответили
pub const TIMEOUT: i64 = 3;
/// Наушники ответили, но значение не то, что просили
pub const REJECTED: i64 = 4;

#[derive(Debug)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    pub data: Option<Value>,
}

impl RpcError {
    pub fn new(code: i64, message: &str) -> Self {
        RpcError { code, message: message.to_string(), data: None }
    }

    pub fn with(mut self, data: Value) -> Self {
        self.data = Some(data);
        self
    }
}

pub fn notification(method: &str, params: Value) -> Value {
    json!({ "jsonrpc": "2.0", "method": method, "params": params })
}

pub fn response(id: Value, result: Result<Value, RpcError>) -> Value {
    match result {
        Ok(result) => json!({ "jsonrpc": "2.0", "id": id, "result": result }),
        Err(e) => {
            let mut error = json!({ "code": e.code, "message": e.message });
            if let Some(data) = e.data {
                error["data"] = data;
            }
            json!({ "jsonrpc": "2.0", "id": id, "error": error })
        }
    }
}

pub struct Request {
    /// None — уведомление, отвечать не надо
    pub id: Option<Value>,
    pub method: String,
    pub params: Value,
}

pub fn parse(line: &str) -> Result<Request, Value> {
    let v: Value =
        serde_json::from_str(line).map_err(|e| response(Value::Null, Err(RpcError::new(PARSE_ERROR, &e.to_string()))))?;
    let id = v.get("id").cloned();
    let bad = |msg: &str| response(id.clone().unwrap_or(Value::Null), Err(RpcError::new(INVALID_REQUEST, msg)));
    if v["jsonrpc"] != "2.0" {
        return Err(bad("нужно \"jsonrpc\": \"2.0\""));
    }
    let method = v["method"].as_str().ok_or_else(|| bad("нет method"))?.to_string();
    let params = v.get("params").cloned().unwrap_or(json!({}));
    Ok(Request { id, method, params })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let r = parse(r#"{"jsonrpc":"2.0","id":7,"method":"set","params":{"id":"noise"}}"#).ok().unwrap();
        assert_eq!((r.id, r.method.as_str(), &r.params["id"]), (Some(json!(7)), "set", &json!("noise")));
        assert!(parse(r#"{"jsonrpc":"2.0","method":"list"}"#).ok().unwrap().id.is_none());
        let e = parse("{oops").err().unwrap();
        assert_eq!(e["error"]["code"], PARSE_ERROR);
        let e = response(json!(3), Err(RpcError::new(TIMEOUT, "нет").with(json!({ "value": 1 }))));
        assert_eq!(e["error"]["data"]["value"], 1);
    }
}
