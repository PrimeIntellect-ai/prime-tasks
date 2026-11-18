#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/run1.log
[2023-10-01T10:00:00] DEBUG Starting run 1
[2023-10-01T10:01:00] INFO Extracted translation -> Key: HELLO | Lang: fr | Value: Bonjour
[2023-10-01T10:01:05] INFO Extracted translation -> Key: GOODBYE | Lang: fr | Value: Au revoir
[2023-10-01T10:02:00] INFO Extracted translation -> Key: HELLO | Lang: es | Value: Hola
[2023-10-01T10:05:00] ERROR Timeout during fetch
EOF

    cat << 'EOF' > /home/user/raw_logs/run2.log
[2023-10-01T11:00:00] DEBUG Starting run 2
[2023-10-01T11:01:00] INFO Extracted translation -> Key: HELLO | Lang: fr | Value: Salut
[2023-10-01T11:01:05] INFO Extracted translation -> Key: CANCEL | Lang: de | Value: Abbrechen
[2023-10-01T11:02:00] INFO Extracted translation -> Key: HELLO | Lang: es | Value: Hola
[2023-10-01T11:05:00] ERROR Timeout during fetch
EOF

    cat << 'EOF' > /home/user/raw_logs/run3.log
[2023-10-01T12:00:00] DEBUG Starting run 3
[2023-10-01T12:01:00] INFO Extracted translation -> Key: LOGIN | Lang: en | Value: Log in
[2023-10-01T12:01:05] INFO Extracted translation -> Key: GOODBYE | Lang: fr | Value: Au revoir
[2023-10-01T12:02:00] INFO Extracted translation -> Key: SAVE | Lang: en | Value: Save
[2023-10-01T12:05:00] INFO Success
EOF

    chown -R user:user /home/user/raw_logs
    chmod -R 777 /home/user
