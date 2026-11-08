#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/rusty-dispatcher/src
    mkdir -p /home/user/diagnostics

    cat << 'EOF' > /home/user/rusty-dispatcher/mock_worker.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "No file provided"
    exit 1
fi
if [ ! -f "$1" ]; then
    echo "File not found: $1"
    exit 1
fi
echo "Processed $1 successfully"
exit 0
EOF
    chmod +x /home/user/rusty-dispatcher/mock_worker.sh

    cat << 'EOF' > /home/user/logs/node_alpha.log
[2023-10-24T08:12:01Z] INFO Worker starting
[2023-10-24T08:15:22Z] INFO Processed /data/inputs/report_q3.csv
[2023-10-24T08:16:05Z] ERROR Failed to execute shell command for file: /data/inputs/financial summary final.pdf - exit code 1
[2023-10-24T08:20:11Z] INFO Processed /data/inputs/metrics.json
EOF

    cat << 'EOF' > /home/user/logs/node_beta.log
[2023-10-24T08:12:05Z] INFO Worker starting
[2023-10-24T08:14:10Z] ERROR Failed to execute shell command for file: /data/inputs/user backups/archive.tar.gz - exit code 1
[2023-10-24T08:19:55Z] INFO Processed /data/inputs/clean_data.txt
EOF

    cat << 'EOF' > /home/user/rusty-dispatcher/Cargo.toml
[package]
name = "rusty-dispatcher"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rusty-dispatcher/src/lib.rs
pub mod processor;
EOF

    cat << 'EOF' > /home/user/rusty-dispatcher/src/processor.rs
use std::process::Command;

pub fn execute_worker_job(filepath: &str) -> Result<(), String> {
    // BUG: Unescaped shell concatenation
    let script_path = "/home/user/rusty-dispatcher/mock_worker.sh";
    let cmd_str = format!("{} {}", script_path, filepath);

    let output = Command::new("sh")
        .arg("-c")
        .arg(&cmd_str)
        .output()
        .map_err(|e| e.to_string())?;

    if output.status.success() {
        Ok(())
    } else {
        Err(format!("Command failed with output: {:?}", output))
    }
}
EOF

    chown -R user:user /home/user/logs /home/user/rusty-dispatcher /home/user/diagnostics
    chmod -R 777 /home/user
