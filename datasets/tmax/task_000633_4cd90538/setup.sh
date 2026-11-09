#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data/logs/2024-01-01
    mkdir -p /home/user/data/logs/2024-01-02
    mkdir -p /home/user/processed
    mkdir -p /app

    cat << 'EOF' > /home/user/data/users.csv
user_id,region,account_type
101,US-East,premium
102,EU-West,basic
103,US-East,basic
EOF

    cat << 'EOF' > /home/user/data/logs/2024-01-01/events.tsv
event_id	user_id	timestamp	metric_value
1001	101	2024-01-01T10:00:00Z	50.5
1002	102	2024-01-01T10:05:00Z	-10.0
1003	103	2024-01-01T10:10:00Z	
1004	101	2024-01-01T10:15:00Z	100.0
EOF

    cat << 'EOF' > /home/user/data/logs/2024-01-02/events.tsv
event_id	user_id	timestamp	metric_value
1005	102	2024-01-02T11:00:00Z	25.0
1006		2024-01-02T11:05:00Z	40.0
1007	101	2024-01-02T11:10:00Z	error
1008	103	2024-01-02T11:15:00Z	10.5
EOF

    cat << 'EOF' > /tmp/anonymizer.c
#include <stdio.h>
#include <stdlib.h>
int main() {
    long long uid, eid;
    if (scanf("%lld %lld", &uid, &eid) == 2) {
        long long res = (uid ^ 0x5A) + (eid ^ 0x5A);
        printf("TKN-%llX\n", res);
    }
    return 0;
}
EOF
    gcc -O3 -s /tmp/anonymizer.c -o /app/anonymizer
    rm /tmp/anonymizer.c
    chmod +x /app/anonymizer

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chown -R user:user /home/user/processed
    chmod -R 777 /home/user
