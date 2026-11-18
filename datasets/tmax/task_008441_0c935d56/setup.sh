#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin /home/user/data

    # Create dummy data > 50MB
    dd if=/dev/zero of=/home/user/data/dummy.dat bs=1M count=60 2>/dev/null

    # Create the helper script
    cat << 'EOF' > /home/user/bin/send_alert.sh
#!/bin/bash
if [ -z "$ALERT_DIR" ]; then
    echo "ALERT_DIR not set" >&2
    exit 1
fi
echo "QUOTA EXCEEDED" > "$ALERT_DIR/email.txt"
EOF
    chmod +x /home/user/bin/send_alert.sh

    # Create the broken wrapper script
    cat << 'EOF' > /home/user/run_monitor.sh
#!/bin/bash
# Broken cron wrapper
/home/user/disk_monitor
EOF
    chmod +x /home/user/run_monitor.sh

    # Create the broken Rust program
    cat << 'EOF' > /home/user/main.rs
use std::process::Command;
use std::fs;

fn main() {
    let size = 0; // BUG: Not calculating dir size

    if size > 50_000_000 {
        // BUG: Hardcoded absolute path, bypassing PATH testing
        Command::new("/home/user/bin/send_alert.sh").status().unwrap();
    }
}
EOF

    chmod -R 777 /home/user
