#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/collector.sh
#!/bin/bash
rm -f /home/user/data/ready.flag
sleep 3
touch /home/user/data/ready.flag
while true; do sleep 60; done
EOF
    chmod +x /home/user/collector.sh

    cat << 'EOF' > /home/user/alerter.rs
use std::fs;
use std::path::Path;
use std::thread;
use std::time::Duration;

fn main() {
    let active_path = Path::new("/home/user/data/active");
    let ready_flag = Path::new("/home/user/data/ready.flag");

    if !ready_flag.exists() {
        eprintln!("CRITICAL: ready.flag not found! Collector must be running and ready.");
        std::process::exit(1);
    }

    if !active_path.exists() {
        eprintln!("CRITICAL: /home/user/data/active does not exist.");
        std::process::exit(1);
    }

    if !fs::symlink_metadata(active_path).unwrap().is_symlink() {
        eprintln!("CRITICAL: /home/user/data/active is not a symlink.");
        std::process::exit(1);
    }

    // Write a heartbeat to prove it's running
    loop {
        fs::write("/home/user/data/alerter.heartbeat", "alive").unwrap();
        thread::sleep(Duration::from_millis(500));
    }
}
EOF

    chmod -R 777 /home/user
