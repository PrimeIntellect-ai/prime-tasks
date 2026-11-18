#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-01 10:00:00] ERROR: データベース接続失敗 metrics:{alpha=3.0;beta=4.0;gamma=0.0}
[2023-10-01 10:05:00] WARN: Ошибка сети metrics:{alpha=1.0;beta=2.0;gamma=2.0}
[2023-10-01 10:10:00] FATAL: النظام معطل metrics:{alpha=4.0;beta=4.0;gamma=2.0}
[2023-10-01 10:15:00] INFO: ﬀ ligature test metrics:{alpha=6.0;beta=0.0;gamma=0.0}
[2023-10-01 10:20:00] DEBUG: ﬁle not found metrics:{x=2.0;y=2.0;z=1.0}
[2023-10-01 10:25:00] ERROR:   𝔄 bad string   metrics:{a=5.0;b=5.0}
EOF

    chmod -R 777 /home/user
