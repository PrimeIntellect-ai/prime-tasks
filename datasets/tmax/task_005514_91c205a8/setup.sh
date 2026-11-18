#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_worker.sh
#!/bin/bash
TOKEN="SYS_TOK_83749201"
TEMP_FILE=$(mktemp)
echo "$TOKEN" > "$TEMP_FILE"
exec 4< "$TEMP_FILE"
rm "$TEMP_FILE"
# Hang indefinitely
while true; do sleep 60; done
EOF
    chmod +x /home/user/legacy_worker.sh

    cat << 'EOF' > /.singularity.d/env/99-worker.sh
#!/bin/bash
if ! pgrep -f legacy_worker.sh > /dev/null; then
    nohup /home/user/legacy_worker.sh > /dev/null 2>&1 &
fi
EOF
    chmod +x /.singularity.d/env/99-worker.sh

    chmod -R 777 /home/user
