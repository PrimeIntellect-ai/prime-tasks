#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        gdb \
        strace \
        jq \
        curl \
        wget \
        vim \
        nano

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app/bin
    mkdir -p /home/user/logs
    mkdir -p /home/user/build_artifacts
    mkdir -p /verify/corpus/clean
    mkdir -p /verify/corpus/evil

    # Write C program for manifest_compiler
    cat << 'EOF' > /tmp/compiler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_target(const char *val) {
    char buf[32];
    strcpy(buf, val);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <manifest.json>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *data = malloc(fsize + 1);
    fread(data, 1, fsize, f);
    fclose(f);
    data[fsize] = '\0';

    char *ptr = data;
    while ((ptr = strstr(ptr, "\"build_target\"")) != NULL) {
        ptr += 14;
        while (*ptr == ' ' || *ptr == ':' || *ptr == '\n' || *ptr == '\r' || *ptr == '\t') ptr++;
        if (*ptr == '"') {
            ptr++;
            char *end = strchr(ptr, '"');
            if (end) {
                int len = end - ptr;
                if (len == 64 && strncmp(ptr, "OBJ_", 4) == 0) {
                    char evil[65];
                    strncpy(evil, ptr, 64);
                    evil[64] = '\0';
                    process_target(evil);
                }
            }
        }
    }

    free(data);
    return 0;
}
EOF

    gcc -O0 -fno-stack-protector -o /app/bin/manifest_compiler /tmp/compiler.c
    strip /app/bin/manifest_compiler
    rm /tmp/compiler.c

    # Generate Logs
    cat << 'EOF' > /home/user/logs/service_A.log
[2023-10-27 10:00:01] INFO: Service A processing manifest 1
[2023-10-27 10:01:01] INFO: Service A processing manifest 2
[2023-10-27 10:02:01] INFO: Service A processing manifest 3
[2023-10-27 10:03:01] INFO: Service A processing manifest 4
[2023-10-27 10:04:01] INFO: Service A processing manifest 5
EOF

    cat << 'EOF' > /home/user/logs/service_B.log
[2023-10-27 10:00:15] INFO: Service B processing manifest 1
[2023-10-27 10:01:15] INFO: Service B processing manifest 2
[2023-10-27 10:02:15] INFO: Service B processing manifest 3
[2023-10-27 10:03:15] INFO: Service B processing manifest 4
[2023-10-27 10:04:15] INFO: Service B processing manifest 5
EOF

    cat << 'EOF' > /home/user/logs/service_C.log
[2023-10-27 10:00:30] INFO: Service C processing manifest 1
[2023-10-27 10:01:30] INFO: Service C processing manifest 2
[2023-10-27 10:02:30] INFO: Service C processing manifest 3
[2023-10-27 10:03:30] INFO: Service C processing manifest 4
[2023-10-27 10:03:31] FATAL: manifest_compiler crashed with signal 11 (Segmentation fault)
EOF

    # Generate Build Artifacts
    cat << 'EOF' > /home/user/build_artifacts/manifest_1.json
{"name": "test1", "build_target": "OBJ_123"}
EOF
    cat << 'EOF' > /home/user/build_artifacts/manifest_2.json
{"name": "test2", "build_target": "OBJ_456"}
EOF
    cat << 'EOF' > /home/user/build_artifacts/manifest_3.json
{"name": "test3", "build_target": "OBJ_789"}
EOF
    cat << 'EOF' > /home/user/build_artifacts/manifest_4.json
{"name": "test4", "build_target": "OBJ_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}
EOF
    cat << 'EOF' > /home/user/build_artifacts/manifest_5.json
{"name": "test5", "build_target": "OBJ_ABC"}
EOF

    # Generate clean corpus
    for i in $(seq 1 100); do
        echo "{\"id\": $i, \"build_target\": \"OBJ_123\"}" > /verify/corpus/clean/clean_$i.json
    done

    # Generate evil corpus
    for i in $(seq 1 100); do
        echo "{\"id\": $i, \"build_target\": \"OBJ_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\"}" > /verify/corpus/evil/evil_$i.json
    done

    chown -R user:user /home/user
    chmod -R 777 /home/user
