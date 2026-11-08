#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/audit

    cat << 'EOF' > /home/user/audit/firewall_rules.json
{
  "policies": [
    {
      "service": "ssh",
      "action": "allow",
      "protocol": "tcp",
      "port": 22
    },
    {
      "service": "internal_file_server",
      "action": "allow",
      "protocol": "tcp",
      "port": 8080
    },
    {
      "service": "database",
      "action": "deny",
      "protocol": "tcp",
      "port": 5432
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/audit/server.rs
use std::io::{Read, Write};
use std::net::TcpListener;

pub fn weak_hash(data: &[u8]) -> u32 {
    let mut hash: u32 = 0;
    for (i, &b) in data.iter().enumerate() {
        hash = hash.wrapping_add((b as u32) * ((i as u32) + 1));
    }
    hash
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 1024];
        stream.read(&mut buffer).unwrap();

        let response = "HTTP/1.1 200 OK\r\n\
                        Content-Type: text/plain\r\n\
                        \r\n\
                        Hello, world!";

        stream.write_all(response.as_bytes()).unwrap();
        stream.flush().unwrap();
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
