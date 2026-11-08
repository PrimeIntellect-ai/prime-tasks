#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat netcat-openbsd gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    cat << 'EOF' > /tmp/anonymizer.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <email>\n", argv[0]);
        return 1;
    }
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "echo -n '%s' | md5sum | awk '{print $1}'", argv[1]);
    int ret = system(cmd);
    return ret == 0 ? 0 : 1;
}
EOF
    gcc /tmp/anonymizer.c -o /app/anonymizer
    strip /app/anonymizer
    rm /tmp/anonymizer.c

    python3 -c '
import random
from datetime import datetime, timedelta

emails = ["alice@example.com", "bob@example.com", "charlie@example.com", "diana@example.com", "eve@example.com"]
payloads = ["{\"action\": \"login\"}", "{\"action\": \"logout\"}", "{\"action\": \"view\", \"item\": 42}", "{\"action\": \"upload\", \"file\": \"data.csv\"}"]

formats = [
    "%b %d %H:%M:%S %Y",
    "%Y/%m/%d %H:%M:%S",
    "%d %b %Y %H:%M:%S"
]

start_date = datetime(2022, 1, 1)

with open("/home/user/raw_syslogs.txt", "w") as f:
    for i in range(100):
        dt = start_date + timedelta(days=random.randint(0, 300), hours=random.randint(0, 23), minutes=random.randint(0, 59), seconds=random.randint(0, 59))
        fmt = random.choice(formats)
        ts_str = dt.strftime(fmt)
        email = random.choice(emails)
        payload = random.choice(payloads)
        ip = f"192.168.1.{random.randint(1, 255)}"
        f.write(f"[{ts_str}] source_ip={ip} user={email} payload={payload}\n")
'

    chmod -R 777 /home/user
