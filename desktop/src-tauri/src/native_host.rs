use std::io::{self, Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::path::PathBuf;
use std::time::Duration;

pub const DEFAULT_PORT: u16 = 31415;
pub const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024; // 10 MB safety ceiling
pub const HOST_NAME: &str = "com.hyperfetch.native_host";

/// Reads a message according to the Chrome Native Messaging protocol:
/// 4 bytes little-endian length prefix, followed by JSON payload.
/// Returns `Ok(None)` on clean EOF at the message boundary.
pub fn read_message<R: Read>(mut reader: R) -> io::Result<Option<serde_json::Value>> {
    let mut len_buf = [0u8; 4];
    match reader.read_exact(&mut len_buf) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    }

    let length = u32::from_le_bytes(len_buf) as usize;
    if length == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Received native messaging message with zero length",
        ));
    }
    if length > MAX_MESSAGE_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "Native messaging payload length {} exceeds maximum allowed ({} bytes)",
                length, MAX_MESSAGE_SIZE
            ),
        ));
    }

    let mut payload = vec![0u8; length];
    reader.read_exact(&mut payload)?;

    let value: serde_json::Value = serde_json::from_slice(&payload)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("Invalid JSON payload: {}", e)))?;

    Ok(Some(value))
}

/// Writes a JSON message according to the Chrome Native Messaging protocol:
/// 4 bytes little-endian length prefix, followed by UTF-8 encoded JSON payload, flushed immediately.
pub fn write_message<W: Write>(mut writer: W, message: &serde_json::Value) -> io::Result<()> {
    let payload = serde_json::to_vec(message)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("Failed to serialize JSON: {}", e)))?;
    let length = payload.len() as u32;

    writer.write_all(&length.to_le_bytes())?;
    writer.write_all(&payload)?;
    writer.flush()?;
    Ok(())
}

/// Checks if a TCP port on localhost is actively accepting connections.
pub fn is_port_responding(port: u16) -> bool {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    TcpStream::connect_timeout(&addr, Duration::from_millis(250)).is_ok()
}

/// Checks if the HyperFetch desktop application is currently running
/// by checking the bridge port (default 31415 or env HYPERFETCH_PORT).
pub fn is_app_running() -> bool {
    let port = std::env::var("HYPERFETCH_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(DEFAULT_PORT);
    is_port_responding(port)
}

/// Locates the main HyperFetch desktop application executable across platforms.
pub fn find_app_executable() -> Option<PathBuf> {
    // 1. Explicit override via environment variable
    if let Ok(env_path) = std::env::var("HYPERFETCH_APP_PATH") {
        let p = PathBuf::from(env_path);
        if p.exists() {
            return Some(p);
        }
    }

    // 2. Relative to the current host binary
    if let Ok(current_exe) = std::env::current_exe() {
        if let Some(parent) = current_exe.parent() {
            #[cfg(windows)]
            {
                let candidates = [
                    parent.join("HyperFetch.exe"),
                    parent.join("desktop.exe"),
                    parent.join("../HyperFetch.exe"),
                    parent.join("../desktop.exe"),
                ];
                for cand in &candidates {
                    if cand.exists() {
                        return Some(cand.clone());
                    }
                }
            }

            #[cfg(target_os = "macos")]
            {
                // Check if running inside an app bundle, e.g. HyperFetch.app/Contents/MacOS/hyperfetch-native-host
                let mut curr = parent;
                for _ in 0..3 {
                    if let Some(ext) = curr.extension() {
                        if ext == "app" && curr.exists() {
                            return Some(curr.to_path_buf());
                        }
                    }
                    if let Some(next_p) = curr.parent() {
                        curr = next_p;
                    } else {
                        break;
                    }
                }

                let candidates = [
                    parent.join("HyperFetch"),
                    parent.join("desktop"),
                    parent.join("../MacOS/HyperFetch"),
                    parent.join("../MacOS/desktop"),
                ];
                for cand in &candidates {
                    if cand.exists() {
                        return Some(cand.clone());
                    }
                }
            }

            #[cfg(not(any(windows, target_os = "macos")))]
            {
                let candidates = [
                    parent.join("HyperFetch"),
                    parent.join("hyperfetch"),
                    parent.join("desktop"),
                ];
                for cand in &candidates {
                    if cand.exists() {
                        return Some(cand.clone());
                    }
                }
            }
        }
    }

    // 3. Known standard system / installation locations
    #[cfg(windows)]
    {
        if let Ok(local_app_data) = std::env::var("LOCALAPPDATA") {
            let p = PathBuf::from(local_app_data).join("Programs/HyperFetch/HyperFetch.exe");
            if p.exists() {
                return Some(p);
            }
        }
        if let Ok(prog_files) = std::env::var("PROGRAMFILES") {
            let p = PathBuf::from(prog_files).join("HyperFetch/HyperFetch.exe");
            if p.exists() {
                return Some(p);
            }
        }
        if let Ok(prog_files_x86) = std::env::var("PROGRAMFILES(X86)") {
            let p = PathBuf::from(prog_files_x86).join("HyperFetch/HyperFetch.exe");
            if p.exists() {
                return Some(p);
            }
        }
        Some(PathBuf::from("HyperFetch.exe"))
    }

    #[cfg(target_os = "macos")]
    {
        let standard_apps = [
            PathBuf::from("/Applications/HyperFetch.app"),
            dirs::home_dir().map(|h| h.join("Applications/HyperFetch.app")).unwrap_or_default(),
            PathBuf::from("build/HyperFetch.app"),
        ];
        for app in &standard_apps {
            if app.exists() {
                return Some(app.clone());
            }
        }
        Some(PathBuf::from("/Applications/HyperFetch.app"))
    }

    #[cfg(not(any(windows, target_os = "macos")))]
    {
        let candidates = [
            PathBuf::from("/usr/local/bin/hyperfetch"),
            PathBuf::from("/usr/bin/hyperfetch"),
            dirs::home_dir().map(|h| h.join(".local/bin/hyperfetch")).unwrap_or_default(),
        ];
        for cand in &candidates {
            if cand.exists() {
                return Some(cand.clone());
            }
        }
        Some(PathBuf::from("hyperfetch"))
    }
}

/// Spawns the main HyperFetch desktop application executable.
pub fn launch_app() -> bool {
    let target = match find_app_executable() {
        Some(t) => t,
        None => {
            eprintln!("[hyperfetch-native-host] Could not locate HyperFetch executable");
            return false;
        }
    };

    #[cfg(target_os = "macos")]
    {
        let path_str = target.to_string_lossy();
        if path_str.ends_with(".app") {
            // macOS bundle: use `open -g` to launch in background without stealing focus
            let open_res = std::process::Command::new("open")
                .arg("-g")
                .arg(&target)
                .spawn();
            if open_res.is_ok() {
                eprintln!("[hyperfetch-native-host] Launched application bundle: {}", path_str);
                return true;
            }
            // Fallback without -g
            match std::process::Command::new("open").arg(&target).spawn() {
                Ok(_) => {
                    eprintln!("[hyperfetch-native-host] Launched application bundle via open: {}", path_str);
                    true
                }
                Err(e) => {
                    eprintln!("[hyperfetch-native-host] Failed to open bundle {}: {}", path_str, e);
                    false
                }
            }
        } else {
            // Direct executable binary
            match std::process::Command::new(&target)
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn()
            {
                Ok(_) => {
                    eprintln!("[hyperfetch-native-host] Launched binary: {}", path_str);
                    true
                }
                Err(e) => {
                    eprintln!("[hyperfetch-native-host] Failed to spawn {}: {}", path_str, e);
                    false
                }
            }
        }
    }

    #[cfg(windows)]
    {
        let mut cmd = std::process::Command::new(&target);
        cmd.stdin(std::process::Stdio::null())
           .stdout(std::process::Stdio::null())
           .stderr(std::process::Stdio::null());

        use std::os::windows::process::CommandExt;
        const DETACHED_PROCESS: u32 = 0x00000008;
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x00000200;
        cmd.creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP);

        match cmd.spawn() {
            Ok(_) => {
                eprintln!("[hyperfetch-native-host] Launched Windows binary: {:?}", target);
                true
            }
            Err(e) => {
                eprintln!("[hyperfetch-native-host] Failed to launch Windows binary {:?}: {}", target, e);
                false
            }
        }
    }

    #[cfg(not(any(windows, target_os = "macos")))]
    {
        match std::process::Command::new(&target)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
        {
            Ok(_) => {
                eprintln!("[hyperfetch-native-host] Launched Linux binary: {:?}", target);
                true
            }
            Err(e) => {
                eprintln!("[hyperfetch-native-host] Failed to launch Linux binary {:?}: {}", target, e);
                false
            }
        }
    }
}

/// Handles an incoming message with default running check and app launcher.
pub fn handle_message(msg: &serde_json::Value) -> serde_json::Value {
    handle_message_with(msg, is_app_running, launch_app)
}

/// Handles an incoming message with custom running check and launcher implementations (for testing).
pub fn handle_message_with<F, L>(
    msg: &serde_json::Value,
    mut check_running: F,
    mut launcher: L,
) -> serde_json::Value
where
    F: FnMut() -> bool,
    L: FnMut() -> bool,
{
    let action = msg
        .get("action")
        .and_then(|a| a.as_str())
        .unwrap_or("launch");

    match action {
        "ping" => {
            let running = check_running();
            serde_json::json!({
                "status": "ok",
                "action": "ping",
                "running": running
            })
        }
        "launch" | _ => {
            let running = check_running();
            if running {
                serde_json::json!({
                    "status": "ok",
                    "action": action,
                    "launched": true,
                    "already_running": true
                })
            } else {
                let launched = launcher();
                serde_json::json!({
                    "status": "ok",
                    "action": action,
                    "launched": launched
                })
            }
        }
    }
}

/// Main loop for stdio Native Messaging host.
pub fn main_loop() {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut reader = stdin.lock();
    let mut writer = stdout.lock();

    while let Ok(Some(msg)) = read_message(&mut reader) {
        let response = handle_message(&msg);
        if let Err(e) = write_message(&mut writer, &response) {
            eprintln!("[hyperfetch-native-host] Failed to write response: {}", e);
            break;
        }
    }
}

/// Generates a standard Chrome Native Messaging Host manifest JSON.
pub fn generate_manifest_json(executable_path: &str) -> String {
    format!(
        r#"{{
  "name": "{}",
  "description": "HyperFetch Chrome Native Messaging Host",
  "path": "{}",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://chhljomijnngbgaglihlgjdbebebfijl/",
    "chrome-extension://*/",
    "chrome-extension://*",
    "edge-extension://*"
  ]
}}"#,
        HOST_NAME, executable_path
    )
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use std::io::Cursor;
    use std::net::TcpListener;

    #[test]
    fn test_read_message_success() {
        let json_data = serde_json::json!({
            "action": "launch",
            "url": "https://example.com/file.zip"
        });
        let payload = serde_json::to_vec(&json_data).unwrap();
        let len = payload.len() as u32;

        let mut raw = Vec::new();
        raw.extend_from_slice(&len.to_le_bytes());
        raw.extend_from_slice(&payload);

        let mut cursor = Cursor::new(raw);
        let result = read_message(&mut cursor).expect("read_message failed");
        assert!(result.is_some());
        let parsed = result.unwrap();
        assert_eq!(parsed["action"], "launch");
        assert_eq!(parsed["url"], "https://example.com/file.zip");
    }

    #[test]
    fn test_read_message_eof_on_empty() {
        let cursor = Cursor::new(Vec::new());
        let result = read_message(cursor).expect("read_message should succeed on EOF");
        assert!(result.is_none());
    }

    #[test]
    fn test_read_message_zero_length_error() {
        let len: u32 = 0;
        let cursor = Cursor::new(len.to_le_bytes().to_vec());
        let result = read_message(cursor);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn test_read_message_exceeds_max_length() {
        let len: u32 = (MAX_MESSAGE_SIZE + 1) as u32;
        let cursor = Cursor::new(len.to_le_bytes().to_vec());
        let result = read_message(cursor);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn test_read_message_incomplete_payload() {
        let len: u32 = 100;
        let mut raw = len.to_le_bytes().to_vec();
        raw.extend_from_slice(b"partial payload");
        let cursor = Cursor::new(raw);
        let result = read_message(cursor);
        assert!(result.is_err());
    }

    #[test]
    fn test_read_message_invalid_json() {
        let not_json = b"this is not valid json";
        let len = not_json.len() as u32;
        let mut raw = len.to_le_bytes().to_vec();
        raw.extend_from_slice(not_json);
        let cursor = Cursor::new(raw);
        let result = read_message(cursor);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn test_write_message_protocol_format() {
        let response = serde_json::json!({
            "status": "ok",
            "launched": true
        });
        let mut output = Vec::new();
        write_message(&mut output, &response).expect("write_message failed");

        assert!(output.len() >= 4);
        let len_bytes: [u8; 4] = output[0..4].try_into().unwrap();
        let length = u32::from_le_bytes(len_bytes) as usize;
        assert_eq!(output.len() - 4, length);

        let decoded: serde_json::Value = serde_json::from_slice(&output[4..]).unwrap();
        assert_eq!(decoded["status"], "ok");
        assert_eq!(decoded["launched"], true);
    }

    #[test]
    fn test_roundtrip_message_serialization() {
        let original = serde_json::json!({
            "status": "ok",
            "action": "ping",
            "running": true,
            "version": "1.0.0"
        });

        let mut buffer = Vec::new();
        write_message(&mut buffer, &original).unwrap();

        let mut cursor = Cursor::new(buffer);
        let roundtrip = read_message(&mut cursor).unwrap().expect("should read message");
        assert_eq!(original, roundtrip);
    }

    #[test]
    fn test_handle_message_ping_running() {
        let msg = serde_json::json!({ "action": "ping" });
        let resp = handle_message_with(&msg, || true, || unreachable!());
        assert_eq!(resp["status"], "ok");
        assert_eq!(resp["action"], "ping");
        assert_eq!(resp["running"], true);
    }

    #[test]
    fn test_handle_message_ping_stopped() {
        let msg = serde_json::json!({ "action": "ping" });
        let resp = handle_message_with(&msg, || false, || unreachable!());
        assert_eq!(resp["status"], "ok");
        assert_eq!(resp["action"], "ping");
        assert_eq!(resp["running"], false);
    }

    #[test]
    fn test_handle_message_launch_already_running() {
        let msg = serde_json::json!({ "action": "launch" });
        let resp = handle_message_with(&msg, || true, || unreachable!());
        assert_eq!(resp["status"], "ok");
        assert_eq!(resp["action"], "launch");
        assert_eq!(resp["launched"], true);
        assert_eq!(resp["already_running"], true);
    }

    #[test]
    fn test_handle_message_launch_triggers_launcher() {
        let msg = serde_json::json!({ "action": "launch" });
        let mut launched_called = false;
        let resp = handle_message_with(
            &msg,
            || false,
            || {
                launched_called = true;
                true
            },
        );
        assert!(launched_called);
        assert_eq!(resp["status"], "ok");
        assert_eq!(resp["action"], "launch");
        assert_eq!(resp["launched"], true);
    }

    #[test]
    fn test_handle_message_launch_failure() {
        let msg = serde_json::json!({ "action": "launch" });
        let resp = handle_message_with(&msg, || false, || false);
        assert_eq!(resp["status"], "ok");
        assert_eq!(resp["action"], "launch");
        assert_eq!(resp["launched"], false);
    }

    #[test]
    fn test_handle_message_default_action() {
        let msg = serde_json::json!({});
        let resp = handle_message_with(&msg, || true, || unreachable!());
        assert_eq!(resp["status"], "ok");
        assert_eq!(resp["launched"], true);
    }

    #[test]
    fn test_is_port_responding_with_listener() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind listener");
        let port = listener.local_addr().unwrap().port();
        assert!(is_port_responding(port));
        drop(listener);
        // Small delay to let OS release socket
        std::thread::sleep(Duration::from_millis(50));
        assert!(!is_port_responding(port));
    }

    #[test]
    fn test_generate_manifest_json() {
        let manifest = generate_manifest_json("hyperfetch-native-host.exe");
        let parsed: serde_json::Value = serde_json::from_str(&manifest).unwrap();
        assert_eq!(parsed["name"], HOST_NAME);
        assert_eq!(parsed["path"], "hyperfetch-native-host.exe");
        assert_eq!(parsed["type"], "stdio");
        assert!(parsed["allowed_origins"].as_array().unwrap().len() >= 3);
    }
}
