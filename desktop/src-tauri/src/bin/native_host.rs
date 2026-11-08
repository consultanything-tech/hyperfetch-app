use desktop_lib::native_host;

fn main() {
    native_host::main_loop();
}

#[cfg(test)]
mod tests {
    use desktop_lib::native_host::*;
    use std::io::Cursor;

    #[test]
    fn test_bin_roundtrip() {
        let msg = serde_json::json!({"action": "ping"});
        let mut buf = Vec::new();
        write_message(&mut buf, &msg).unwrap();
        let mut cursor = Cursor::new(buf);
        let read = read_message(&mut cursor).unwrap().unwrap();
        assert_eq!(read["action"], "ping");
    }
}
