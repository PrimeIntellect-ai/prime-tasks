#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat curl
    pip3 install pytest

    mkdir -p /home/user/src /home/user/bin /home/user/dashboard /home/user/backup

    cat << 'EOF' > /home/user/src/collector.c
#include <stdio.h>

int main() {
    FILE *f = fopen("./metrics.json", "w");
    if (f == NULL) return 1;
    fprintf(f, "{\"status\": \"ok\", \"active_users\": 42}\n");
    fclose(f);
    return 0;
}
EOF

    gcc /home/user/src/collector.c -o /home/user/bin/collector

    cat << 'EOF' > /home/user/cron_task.sh
#!/bin/bash
while true; do
    cd /home/user
    /home/user/bin/collector
    sleep 60
done
EOF
    chmod +x /home/user/cron_task.sh

    useradd -m -s /bin/bash user || true

    # Start the python server in the background when a shell is opened
    echo "cd /home/user/dashboard && python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 &" >> /home/user/.bashrc
    echo "cd /home/user" >> /home/user/.bashrc

    chmod -R 777 /home/user
