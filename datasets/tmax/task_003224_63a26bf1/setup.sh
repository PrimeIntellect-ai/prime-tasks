#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl rustc cargo python3-opencv
pip3 install pytest numpy opencv-python

mkdir -p /app /home/user/data /home/user/logd/src
cd /app

cat << 'EOF' > make_video.py
import cv2
import numpy as np

key_binary = "1010101111001101"
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/error_signal.mp4', fourcc, 1.0, (100, 100))

for bit in key_binary:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if bit == '1':
        frame[0:50, 0:50] = (255, 255, 255)
    out.write(frame)
out.release()
EOF
python3 make_video.py

cat << 'EOF' > make_wal.py
import struct

seed_bytes = struct.pack('>H', 43981)

def encode_record(rec_id, text):
    raw = text.encode('utf-8')
    payload = bytearray()
    for i, b in enumerate(raw):
        payload.append(b ^ seed_bytes[i % 2])
    return struct.pack('<II', rec_id, len(payload)) + payload

with open('/home/user/data/store.wal', 'wb') as f:
    f.write(encode_record(1, "SYSTEM_STARTUP"))
    f.write(encode_record(2, "USER_LOGIN_SUCCESS"))
    # Corrupt record: Length says 100, but only 4 bytes of payload written
    f.write(struct.pack('<II', 3, 100) + b'DEAD')
    f.write(encode_record(4, "CRITICAL_SYSTEM_RECOVERED"))
EOF
python3 make_wal.py

cd /home/user/logd
cat << 'EOF' > Cargo.toml
[package]
name = "logd"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
EOF

cat << 'EOF' > src/wal.rs
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

pub fn load_wal(path: &str) -> std::collections::HashMap<u32, String> {
    let mut map = std::collections::HashMap::new();
    let mut file = File::open(path).unwrap();

    loop {
        let mut id_buf = [0u8; 4];
        if file.read_exact(&mut id_buf).is_err() { break; }
        let id = u32::from_le_bytes(id_buf);

        let mut len_buf = [0u8; 4];
        file.read_exact(&mut len_buf).unwrap();
        let len = u32::from_le_bytes(len_buf) as usize;

        let mut payload = vec![0u8; len];
        // BUG: Will panic on the corrupted record because EOF is reached before `len` bytes
        file.read_exact(&mut payload).unwrap(); 

        // BUG: Not XORing with the magic seed
        let text = String::from_utf8(payload).unwrap();
        map.insert(id, text);
    }
    map
}
EOF

cat << 'EOF' > src/main.rs
mod wal;
use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::main]
async fn main() {
    let db = wal::load_wal("/home/user/data/store.wal");
    let listener = TcpListener::bind("127.0.0.1:8888").await.unwrap();

    loop {
        let (mut socket, _) = listener.accept().await.unwrap();
        let db_clone = db.clone();

        // BUG: The task ignores disconnection and spins forever if read fails without handling
        tokio::spawn(async move {
            let mut buf = [0; 1024];
            let n = socket.read(&mut buf).await.unwrap();
            let req = String::from_utf8_lossy(&buf[..n]);

            if req.starts_with("GET /record/") {
                let id_str = req.trim().split('/').last().unwrap().split(' ').next().unwrap();
                if let Ok(id) = id_str.parse::<u32>() {
                    if let Some(val) = db_clone.get(&id) {
                        let res = format!("HTTP/1.1 200 OK\r\n\r\n{}", val);
                        socket.write_all(res.as_bytes()).await.unwrap();
                        return;
                    }
                }
            }
            let res = "HTTP/1.1 404 NOT FOUND\r\n\r\n";
            socket.write_all(res.as_bytes()).await.unwrap();
        });
    }
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
