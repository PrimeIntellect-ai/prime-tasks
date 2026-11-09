#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 binutils
    pip3 install pytest

    mkdir -p /home/user/legacy_app/bin /home/user/legacy_app/core_dumps

    dd if=/dev/urandom of=/home/user/legacy_app/core_dumps/core.9999 bs=1K count=10
    echo "CRITICAL_TX_HANG: TX-99382-ALPHA" >> /home/user/legacy_app/core_dumps/core.9999
    dd if=/dev/urandom of=/home/user/legacy_app/core_dumps/core.9999 bs=1K count=10 oflag=append conv=notrunc

    cat << 'EOF' > /tmp/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (getenv("BYPASS_LEGACY_LOCKS") == NULL) {
        while(1) { sleep(1); } // Deadlock simulation
    }
    return 0;
}
EOF

    gcc /tmp/processor.c -o /home/user/legacy_app/bin/processor
    rm /tmp/processor.c

    sqlite3 /home/user/legacy_app/data.db "CREATE TABLE queue (id INTEGER, payload TEXT, status TEXT);"
    sqlite3 /home/user/legacy_app/data.db "INSERT INTO queue VALUES (1, 'A', 'PENDING'), (2, 'B', 'PENDING');"

    cat << 'EOF' > /home/user/legacy_app/runner.sh
#!/bin/bash
# runner.sh - Process queue
cd /home/user/legacy_app

sqlite3 data.db "SELECT id, payload FROM queue WHERE status='PENDING';" | while IFS='|' read -r id payload; do
    ./bin/processor "$payload" &
done
wait
echo "All processing done."

sqlite3 results.db "CREATE TABLE IF NOT EXISTS completed (id INTEGER, value INTEGER);"
sqlite3 results.db "INSERT INTO completed VALUES (1, 100), (2, 250), (3, 150);"
EOF

    chmod +x /home/user/legacy_app/runner.sh /home/user/legacy_app/bin/processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
