//! Black-box contract test: build the real binary, run it on an ephemeral
//! port, and assert the /healthz and /version responses from STANDARD.md.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

fn spawn_app(port: u16) -> Child {
    let bin = env!("CARGO_BIN_EXE_sample_app");
    Command::new(bin)
        .env("PORT", port.to_string())
        .env("SERVICE_NAME", "sample-rust")
        .env("APP_VERSION", "9.9.9-test")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn app")
}

/// Send one HTTP GET and read the full response, retrying only while the app
/// has not bound its port yet. Each attempt opens a fresh socket carrying a
/// complete request, so we never leave a half-open probe for the single-
/// threaded server to consume as a (bogus) first request.
fn get(port: u16, path: &str) -> String {
    let addr = format!("127.0.0.1:{port}");
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        match TcpStream::connect(&addr) {
            Ok(mut sock) => {
                sock.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
                let req = format!(
                    "GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
                );
                if sock.write_all(req.as_bytes()).is_ok() {
                    let mut buf = Vec::new();
                    if sock.read_to_end(&mut buf).is_ok() {
                        return String::from_utf8_lossy(&buf).into_owned();
                    }
                }
                // Connected but the exchange failed (app not fully ready):
                // fall through and retry until the deadline.
            }
            Err(_) => {
                assert!(Instant::now() < deadline, "app did not start in time");
            }
        }
        thread::sleep(Duration::from_millis(50));
    }
}

#[test]
fn healthz_returns_ok() {
    let port = 30701;
    let mut child = spawn_app(port);
    let resp = get(port, "/healthz");
    child.kill().unwrap();
    assert!(resp.contains("200 OK"), "response: {resp}");
    assert!(resp.contains(r#"{"status":"ok"}"#), "response: {resp}");
}

#[test]
fn version_reports_service_and_version() {
    let port = 30702;
    let mut child = spawn_app(port);
    let resp = get(port, "/version");
    child.kill().unwrap();
    assert!(resp.contains("200 OK"), "response: {resp}");
    assert!(resp.contains("\"service\":\"sample-rust\""), "response: {resp}");
    assert!(resp.contains("\"version\":\"9.9.9-test\""), "response: {resp}");
}
