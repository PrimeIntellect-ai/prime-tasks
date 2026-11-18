#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/upload_handler.rs
use std::io::Write;

pub fn handle_upload(filename: &str, data: &[u8]) -> std::io::Result<()> {
    // Vulnerable: Directly concatenating user input into a file path
    let save_path = format!("/var/www/uploads/{}", filename);
    let mut file = std::fs::File::create(save_path)?;
    file.write_all(data)?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/traffic.json
[
  {
    "ip": "192.168.1.15",
    "method": "POST",
    "path": "/api/upload",
    "payload": {
      "filename": "avatar.jpg"
    }
  },
  {
    "ip": "10.4.4.200",
    "method": "POST",
    "path": "/api/upload",
    "payload": {
      "filename": "report_final.pdf"
    }
  },
  {
    "ip": "172.16.0.42",
    "method": "POST",
    "path": "/api/upload",
    "payload": {
      "filename": "../../../../../../home/user/.ssh/authorized_keys"
    }
  },
  {
    "ip": "192.168.1.22",
    "method": "POST",
    "path": "/api/upload",
    "payload": {
      "filename": "image_2023.png"
    }
  }
]
EOF

    chmod -R 777 /home/user
