#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 build-essential gdb
    pip3 install pytest

    mkdir -p /home/user/
    cd /home/user/

    cat << 'EOF' > check_status.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Usage: %s <url>\n", argv[0]);
        return 1;
    }

    // Deliberate buffer overflow vulnerability for strings > 60 chars (plus null terminator space)
    char buffer[60];
    strcpy(buffer, argv[1]); 

    printf("Successfully checked %s\n", buffer);
    return 0;
}
EOF

    gcc -g -fno-stack-protector -z execstack -o check_status check_status.c

    python3 -c "
import sqlite3, os, signal
conn = sqlite3.connect('monitor.db')
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE endpoints (id INTEGER PRIMARY KEY, url TEXT, status TEXT);')
conn.execute(\"INSERT INTO endpoints (url, status) VALUES ('http://example.com/api/v1/health', 'pending');\")
conn.execute(\"INSERT INTO endpoints (url, status) VALUES ('https://internal-service.local/ping', 'pending');\")
conn.commit()
conn.execute(\"INSERT INTO endpoints (url, status) VALUES ('https://this-is-a-very-long-url-that-will-cause-a-buffer-overflow.com/ping', 'pending');\")
conn.execute(\"INSERT INTO endpoints (url, status) VALUES ('http://localhost:8080/metrics', 'pending');\")
conn.commit()
os.kill(os.getpid(), signal.SIGKILL)
" || true

    cat << 'EOF' > uptime-monitor.sh
#!/bin/bash

DB="/home/user/monitor.db"
URLS=$(sqlite3 "$DB" "SELECT url FROM endpoints WHERE status='pending';")

for url in $URLS; do
    echo "Processing $url"
    /home/user/check_status "$url"
done
EOF

    chmod +x uptime-monitor.sh
    chmod +x check_status

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/
    chmod -R 777 /home/user
