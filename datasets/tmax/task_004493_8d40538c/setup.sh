#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create the app directory and the binary
    mkdir -p /app
    cat << 'EOF' > /app/ts_aggregator.c
#include <stdio.h>
int main() {
    char buffer[1024];
    while (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        printf("%s", buffer);
    }
    return 0;
}
EOF
    gcc -o /app/ts_aggregator /app/ts_aggregator.c
    strip /app/ts_aggregator
    rm /app/ts_aggregator.c

    # Create corpora directories
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Populate clean corpus
    cat << 'EOF' > /home/user/corpora/clean/clean1.jsonl
{"ts": "2023-01-01T00:00:00Z", "sensor_id": "A1", "msg": "All good here!"}
{"ts": "2023-01-01T00:01:00Z", "sensor_id": "A2", "msg": "System nominal."}
EOF

    # Populate evil corpus
    cat << 'EOF' > /home/user/corpora/evil/evil1.jsonl
{"ts": "2023-01-01T00:00:00Z", "sensor_id": "A1", "msg": "Bad unicode \uD800"}
{"ts": "2023-01-01T00:01:00Z", "sensor_id": "A2"}
{"ts": "2023-01-01T00:02:00Z", "sensor_id": "A3", "msg": "Invalid hex \u12XZ"}
Not a JSON line at all
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
