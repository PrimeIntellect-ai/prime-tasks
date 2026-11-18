#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create C source for data_ingest
    cat << 'EOF' > /app/data_ingest.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void process_line(char *line) {
    long long user_id = 0;
    long long timestamp = 0;
    char *user_id_ptr = strstr(line, "\"user_id\":");
    char *timestamp_ptr = strstr(line, "\"timestamp\":");

    if (user_id_ptr && timestamp_ptr) {
        sscanf(user_id_ptr, "\"user_id\": %lld", &user_id);
        sscanf(timestamp_ptr, "\"timestamp\": %lld", &timestamp);

        if (timestamp % 7 == 0) {
            long long mutated_user_id = user_id ^ 0xDEADBEEF;
            if (mutated_user_id > 0) mutated_user_id = -mutated_user_id;

            // Very hacky JSON modification for simulation
            char output[2048];
            snprintf(output, sizeof(output), "{\"user_id\": %lld, \"timestamp\": %lld, \"event\": \"data_processed\", \"sys_flag\": \"1\"}\n", mutated_user_id, timestamp);
            printf("%s", output);
            return;
        }
    }
    printf("%s", line);
}

int main(int argc, char *argv[]) {
    FILE *fp = stdin;
    if (argc > 1) {
        fp = fopen(argv[1], "r");
        if (!fp) return 1;
    }

    char line[1024];
    while (fgets(line, sizeof(line), fp)) {
        process_line(line);
    }

    if (argc > 1) {
        fclose(fp);
        unlink(argv[1]);
    }
    return 0;
}
EOF

    gcc -O2 /app/data_ingest.c -o /app/data_ingest
    strip -s /app/data_ingest
    rm /app/data_ingest.c

    # Generate logs
    cat << 'EOF' > /app/generate_logs.py
import json
import random

clean_logs = []
evil_logs = []

for i in range(100):
    # Clean log
    ts = 1600000000 + i * 7 + 1 # not divisible by 7
    uid = random.randint(1000, 9999)
    clean_logs.append(json.dumps({"user_id": uid, "timestamp": ts, "event": "data_processed"}))

    # Evil log
    ts_evil = 1600000000 + i * 7 # divisible by 7
    uid_evil = random.randint(1000, 9999)
    mutated_uid = -(uid_evil ^ 0xDEADBEEF)
    evil_logs.append(json.dumps({"user_id": mutated_uid, "timestamp": ts_evil, "event": "data_processed", "sys_flag": "1"}))

with open('/app/corpus/clean/clean_logs.txt', 'w') as f:
    f.write('\n'.join(clean_logs) + '\n')

with open('/app/corpus/evil/evil_logs.txt', 'w') as f:
    f.write('\n'.join(evil_logs) + '\n')
EOF

    python3 /app/generate_logs.py
    rm /app/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
