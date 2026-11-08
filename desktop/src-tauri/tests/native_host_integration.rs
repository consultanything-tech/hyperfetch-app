use std::io::{Read, Write};
use std::process::{Command, Stdio};

#[test]
fn test_native_host_binary_end_to_end() {
    let bin_path = env!("CARGO_BIN_EXE_hyperfetch-native-host");
    let mut child = Command::new(bin_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("Failed to spawn hyperfetch-native-host");

    let mut stdin = child.stdin.take().expect("Failed to open stdin");
    let mut stdout = child.stdout.take().expect("Failed to open stdout");

    // Message 1: Ping
    let ping_msg = serde_json::json!({
        "action": "ping"
    });
    let ping_bytes = serde_json::to_vec(&ping_msg).unwrap();
    let len = ping_bytes.len() as u32;

    stdin.write_all(&len.to_le_bytes()).unwrap();
    stdin.write_all(&ping_bytes).unwrap();
    stdin.flush().unwrap();

    // Read response for Message 1
    let mut resp_len_buf = [0u8; 4];
    stdout.read_exact(&mut resp_len_buf).unwrap();
    let resp_len = u32::from_le_bytes(resp_len_buf) as usize;
    assert!(resp_len > 0);

    let mut resp_buf = vec![0u8; resp_len];
    stdout.read_exact(&mut resp_buf).unwrap();
    let resp_json: serde_json::Value = serde_json::from_slice(&resp_buf).unwrap();

    assert_eq!(resp_json["status"], "ok");
    assert_eq!(resp_json["action"], "ping");
    assert!(resp_json.get("running").is_some());

    // Message 2: Launch with already_running or simulated
    let launch_msg = serde_json::json!({
        "action": "launch"
    });
    let launch_bytes = serde_json::to_vec(&launch_msg).unwrap();
    let len = launch_bytes.len() as u32;

    stdin.write_all(&len.to_le_bytes()).unwrap();
    stdin.write_all(&launch_bytes).unwrap();
    stdin.flush().unwrap();

    // Read response for Message 2
    stdout.read_exact(&mut resp_len_buf).unwrap();
    let resp_len = u32::from_le_bytes(resp_len_buf) as usize;
    let mut resp_buf = vec![0u8; resp_len];
    stdout.read_exact(&mut resp_buf).unwrap();
    let resp_json: serde_json::Value = serde_json::from_slice(&resp_buf).unwrap();

    assert_eq!(resp_json["status"], "ok");
    assert!(resp_json.get("launched").is_some());

    // Close stdin to signal EOF and assert child exits
    drop(stdin);
    let status = child.wait().expect("child failed to exit");
    assert!(status.success());
}
