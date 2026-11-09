#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc jq coreutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/target_system/src
    mkdir -p /home/user/target_system/config

    cat << 'EOF' > /home/user/target_system/src/main.rs
use std::process::Command;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("Usage: fast_backup <target_file>");
        return;
    }

    let file_path = &args[1];

    // Vulnerable to command injection
    let cmd = format!("cp {} /var/backups/archive/ && echo 'Backup complete'", file_path);

    let output = Command::new("sh")
        .arg("-c")
        .arg(&cmd)
        .output()
        .expect("Failed to execute process");

    println!("{}", String::from_utf8_lossy(&output.stdout));
}
EOF

    ACTUAL_HASH=$(sha256sum /home/user/target_system/src/main.rs | awk '{print $1}')

    cat << EOF > /home/user/target_system/releases.txt
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  v1.0.0
8d25f77839db432dbfecceec268c1735d4508ecf6f0ea9db25f9b4009bb333a5  v1.0.1
$ACTUAL_HASH  v1.0.2
f81e64cb05f1d1f038f4625b152ab9f54b6db4cda07b0ccb3b1dfbd5bc9ebc22  v1.1.0
EOF

    cat << 'EOF' > /home/user/target_system/config/sudoers_rules
# Web application deployment sudoers
www-data ALL=(backup_admin) NOPASSWD: /opt/internal/fast_backup
EOF

    chown -R user:user /home/user/target_system
    chmod -R 777 /home/user
