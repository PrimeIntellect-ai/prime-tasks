#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gcc make
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/src
    cd /app/src

    # Download cJSON
    wget https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.h
    wget https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.c

    # Create the query_engine C source
    cat << 'EOF' > query_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cJSON.h"

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *data = malloc(len + 1);
    fread(data, 1, len, f);
    fclose(f);
    data[len] = '\0';

    cJSON *json = cJSON_Parse(data);
    if (!json) return 1;

    cJSON *limit = cJSON_GetObjectItemCaseSensitive(json, "limit");
    if (!limit || !cJSON_IsNumber(limit) || limit->valueint > 100) return 1;

    cJSON *traverse = cJSON_GetObjectItemCaseSensitive(json, "traverse");
    if (traverse) {
        cJSON *depth = cJSON_GetObjectItemCaseSensitive(traverse, "depth");
        cJSON *sp = cJSON_GetObjectItemCaseSensitive(traverse, "shortest_path");
        int d = (depth && cJSON_IsNumber(depth)) ? depth->valueint : 0;
        int is_sp = (sp && cJSON_IsTrue(sp)) ? 1 : 0;
        if (is_sp) {
            if (d > 10) return 1;
        } else {
            if (d > 3) return 1;
        }
    }

    cJSON *cm = cJSON_GetObjectItemCaseSensitive(json, "cross_mapping");
    if (cm) {
        cJSON *idx = cJSON_GetObjectItemCaseSensitive(cm, "indexed");
        if (!idx || !cJSON_IsTrue(idx)) return 1;
    }

    cJSON_Delete(json);
    free(data);
    return 0;
}
EOF

    gcc -O2 query_engine.c cJSON.c -o /app/query_engine
    strip /app/query_engine
    chmod +x /app/query_engine

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"limit": 10}
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.json
{"limit": 100, "traverse": {"depth": 3}}
EOF
    cat << 'EOF' > /app/corpus/clean/clean3.json
{"limit": 50, "traverse": {"depth": 10, "shortest_path": true}}
EOF
    cat << 'EOF' > /app/corpus/clean/clean4.json
{"limit": 20, "cross_mapping": {"indexed": true}}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"limit": 101}
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.json
{"traverse": {"depth": 3}}
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.json
{"limit": 10, "traverse": {"depth": 4}}
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.json
{"limit": 10, "traverse": {"depth": 11, "shortest_path": true}}
EOF
    cat << 'EOF' > /app/corpus/evil/evil5.json
{"limit": 10, "cross_mapping": {"indexed": false}}
EOF
    cat << 'EOF' > /app/corpus/evil/evil6.json
{"limit": 10, "cross_mapping": {}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
