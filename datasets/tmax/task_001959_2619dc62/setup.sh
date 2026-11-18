#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind wget tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    cd /app
    wget -qO cjson.tar.gz https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar -xzf cjson.tar.gz
    rm cjson.tar.gz
    sed -i 's/-fPIC//g' /app/cJSON-1.7.15/Makefile

    mkdir -p /home/user/parser_app

    cat << 'EOF' > /home/user/parser_app/semver_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cJSON.h"

typedef struct {
    int major;
    int minor;
    int patch;
} SemVer;

SemVer* parse_semver(const char* str) {
    SemVer* v = (SemVer*)malloc(sizeof(SemVer));
    if (str[0] == 'v') str++;
    sscanf(str, "%d.%d.%d", &v->major, &v->minor, &v->patch);
    return v;
}

int compare_semver(SemVer* a, SemVer* b) {
    if (a->major != b->major) return a->major - b->major;
    if (a->minor != b->minor) return a->minor - b->minor;
    return a->patch - b->patch;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "r");
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* data = (char*)malloc(len + 1);
    fread(data, 1, len, f);
    fclose(f);
    data[len] = '\0';

    cJSON* json = cJSON_Parse(data);
    free(data);

    SemVer* max_v = NULL;

    cJSON* item = NULL;
    cJSON_ArrayForEach(item, json) {
        SemVer* v = parse_semver(item->valuestring);
        if (!max_v) {
            max_v = v;
        } else {
            if (compare_semver(v, max_v) > 0) {
                max_v = v;
            }
        }
    }

    FILE* out = fopen("/home/user/highest_version.txt", "w");
    if (max_v) {
        fprintf(out, "%d.%d.%d\n", max_v->major, max_v->minor, max_v->patch);
    }
    fclose(out);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/parser_app/generate_json.py
import json
import random

versions = [f"v{random.randint(0,8)}.{random.randint(0,99)}.{random.randint(0,99)}" for _ in range(9999)]
versions.append("v9.99.99")
random.shuffle(versions)

with open('/home/user/parser_app/versions.json', 'w') as f:
    json.dump(versions, f)
EOF

    python3 /home/user/parser_app/generate_json.py
    rm /home/user/parser_app/generate_json.py

    chmod -R 777 /home/user
