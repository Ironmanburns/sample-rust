use std::env;
use std::io::{Read, Write};
use std::net::TcpListener;

fn main() {
    let port = env::var("PORT").unwrap_or_else(|_| "8080".into());
    let service = env::var("SERVICE_NAME").unwrap_or_else(|_| "sample-rust".into());
    let version = env::var("APP_VERSION").unwrap_or_else(|_| "0.1.0".into());
    let listener = TcpListener::bind(format!("0.0.0.0:{port}")).expect("bind");
    eprintln!("{service} listening on {port}");
    for stream in listener.incoming() {
        if let Ok(mut stream) = stream {
            let mut buf = [0u8; 1024];
            let _ = stream.read(&mut buf);
            let req = String::from_utf8_lossy(&buf);
            let (status, body) = if req.starts_with("GET /healthz") {
                ("200 OK", r#"{"status":"ok"}"#.to_string())
            } else if req.starts_with("GET /version") {
                (
                    "200 OK",
                    format!(r#"{{"version":"{version}","service":"{service}"}}"#),
                )
            } else {
                ("404 Not Found", r#"{"error":"not_found"}"#.to_string())
            };
            let resp = format!(
                "HTTP/1.1 {status}\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(resp.as_bytes());
        }
    }
}
