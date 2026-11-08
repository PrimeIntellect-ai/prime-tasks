#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create evidence directory
    mkdir -p /home/user/evidence
    cd /home/user/evidence

    # Create proc_cmdline.b64
    printf "sudo\x00/usr/bin/python3\x00/var/tmp/rogue_proxy.py\x00--listen=0.0.0.0:8443\x00--master-auth-token=xK9v_zP4!mQ2\x00--quiet\x00" > proc_cmdline.raw
    base64 proc_cmdline.raw > /home/user/evidence/proc_cmdline.b64
    rm proc_cmdline.raw

    # Create http_logs.jsonl
    cat << 'EOF' > /home/user/evidence/http_logs.jsonl
{"timestamp": "2023-10-25T10:00:00Z", "method": "GET", "url": "/api/public/status", "headers": {"Host": "api.internal", "User-Agent": "curl/7.68.0"}, "cookies": "", "body": ""}
{"timestamp": "2023-10-25T10:05:12Z", "method": "POST", "url": "/api/admin/dump_db", "headers": {"Host": "api.internal", "Authorization": "Bearer xK9v_zP4!mQ2"}, "cookies": "", "body": "SELECT * FROM users;"}
{"timestamp": "2023-10-25T10:15:30Z", "method": "GET", "url": "/api/user/profile", "headers": {"Host": "api.internal", "Authorization": "Bearer valid_user_token"}, "cookies": "session=valid_user_token", "body": ""}
{"timestamp": "2023-10-25T10:22:45Z", "method": "POST", "url": "/api/admin/exfiltrate", "headers": {"Host": "api.internal", "Content-Type": "application/json"}, "cookies": "tracking=123; session=xK9v_zP4!mQ2; prefs=dark", "body": "{\"stolen_keys\": [\"ssh-rsa AAAA...\", \"ssh-ed25519 AAAA...\"]}"}
{"timestamp": "2023-10-25T10:25:00Z", "method": "GET", "url": "/api/public/assets/logo.png", "headers": {"Host": "api.internal"}, "cookies": "session=another_token", "body": ""}
EOF

    # Create expected_cleaned_logs.jsonl
    cat << 'EOF' > /home/user/evidence/expected_cleaned_logs.jsonl
{"timestamp": "2023-10-25T10:00:00Z", "method": "GET", "url": "/api/public/status", "headers": {"Host": "api.internal", "User-Agent": "curl/7.68.0"}, "cookies": "", "body": ""}
{"timestamp": "2023-10-25T10:05:12Z", "method": "POST", "url": "/api/admin/dump_db", "headers": {"Host": "api.internal", "Authorization": "Bearer [REDACTED]"}, "cookies": "", "body": "[REDACTED]"}
{"timestamp": "2023-10-25T10:15:30Z", "method": "GET", "url": "/api/user/profile", "headers": {"Host": "api.internal", "Authorization": "Bearer valid_user_token"}, "cookies": "session=valid_user_token", "body": ""}
{"timestamp": "2023-10-25T10:22:45Z", "method": "POST", "url": "/api/admin/exfiltrate", "headers": {"Host": "api.internal", "Content-Type": "application/json"}, "cookies": "tracking=123; session=[REDACTED]; prefs=dark", "body": "[REDACTED]"}
{"timestamp": "2023-10-25T10:25:00Z", "method": "GET", "url": "/api/public/assets/logo.png", "headers": {"Host": "api.internal"}, "cookies": "session=another_token", "body": ""}
EOF

    # Install Rust for the user as well, or make it system-wide
    # Since we installed it in /root, let's just install it in /opt/rust or copy it
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    ln -s /opt/rust/bin/* /usr/local/bin/

    chmod -R 777 /home/user
