#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "TARGET_PORT: 8899", fill=(0, 0, 0))
d.text((10, 50), "SECRET_TOKEN: EDGE-MIGRATE-2024", fill=(0, 0, 0))
img.save('/app/target_config.png')
EOF
    python3 /tmp/make_image.py

    mkdir -p /home/user/health_monitor/src
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/health_monitor/Cargo.toml
[package]
name = "monitor"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/health_monitor/src/main.rs
fn main() {
    let port = "0000"; // TODO: Update from config
    let token = "UNKNOWN"; // TODO: Update from config
    println!("Connecting to 127.0.0.1:{} with token {}", port, token);
}
EOF

    cat << 'EOF' > /home/user/run_monitor.sh
#!/bin/bash
# Cron environment missing PATH simulation
cd /tmp
/home/user/health_monitor/target/release/monitor > monitor.log
EOF
    chmod +x /home/user/run_monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
