#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make acl
    pip3 install pytest

    mkdir -p /app/sensor-agent-1.0.0

    cat << 'EOF' > /app/sensor-agent-1.0.0/main.c
#include <stdio.h>
#include <math.h>
#include <unistd.h>

int main() {
    double val = sqrt(16.0);
    printf("Sensor agent running. %f\n", val);
    while(1) {
        sleep(10);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/sensor-agent-1.0.0/Makefile
sensor-agent: main.c
	gcc -o sensor-agent main.c
EOF

    mkdir -p /app/corpus
    cat << 'EOF' > /app/corpus/evil.txt
temp=45; rm -rf /
metric=$(whoami)
file=../../../etc/passwd
test&test
test|test
EOF

    cat << 'EOF' > /app/corpus/clean.txt
sensor_id=12,temp=45.2
status=active
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
