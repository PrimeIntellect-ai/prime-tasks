#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl sqlite3 build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    ln -s /opt/cargo/bin/* /usr/local/bin/

    mkdir -p /home/user
    cat << 'EOF' > /home/user/logs.json
[
  {"ts": 1672531200, "code": 500, "msg": "Внутренняя Ошибка Сервера", "host": "alpha-01"},
  {"ts": 1672531205, "code": 404, "msg": "Not Found", "host": "beta-02"},
  {"ts": 1672531210, "code": 403, "msg": "アクセス拒否", "host": "gamma-03"},
  {"ts": 1672531215, "code": 503, "msg": "Сервис Недоступен", "host": "alpha-01"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /opt/cargo /opt/rust || true
