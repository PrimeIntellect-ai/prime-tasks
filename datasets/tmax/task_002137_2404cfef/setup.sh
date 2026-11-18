#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create legacy_validator.c
    cat << 'EOF' > /app/legacy_validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

long parse_iso8601(const char *str) {
    struct tm t = {0};
    int y, M, d, h, m, s;
    if (sscanf(str, "%d-%d-%dT%d:%d:%dZ", &y, &M, &d, &h, &m, &s) == 6) {
        t.tm_year = y - 1900;
        t.tm_mon = M - 1;
        t.tm_mday = d;
        t.tm_hour = h;
        t.tm_min = m;
        t.tm_sec = s;
        return mktime(&t);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[4096];

    char hosts[100][64] = {0};
    long last_time[100] = {0};
    int num_hosts = 0;

    while (fgets(line, sizeof(line), f)) {
        char *msg = strstr(line, "\"message\": \"");
        if (msg) {
            msg += 12;
            char *p = msg;
            while (*p && *p != '"') {
                if (*p == '\\' && *(p+1) == 'u') {
                    int val;
                    if (sscanf(p+2, "%4x", &val) == 1) {
                        if (val >= 0xD800 && val <= 0xDBFF) {
                            int next_val = -1;
                            if (p[6] == '\\' && p[7] == 'u') {
                                sscanf(p+8, "%4x", &next_val);
                            }
                            if (next_val < 0xDC00 || next_val > 0xDFFF) {
                                char *crash = NULL;
                                *crash = 1;
                            }
                        }
                    }
                }
                p++;
            }
        }

        char host[64] = {0};
        char *h = strstr(line, "\"host_id\": \"");
        if (h) {
            h += 12;
            int i = 0;
            while (h[i] && h[i] != '"' && i < 63) {
                host[i] = h[i];
                i++;
            }
        }

        long ts = 0;
        char *t = strstr(line, "\"timestamp\": \"");
        if (t) {
            t += 14;
            ts = parse_iso8601(t);
        }

        int metric_is_null = 0;
        if (strstr(line, "\"metric\": null")) {
            metric_is_null = 1;
        }

        int host_idx = -1;
        for (int i=0; i<num_hosts; i++) {
            if (strcmp(hosts[i], host) == 0) {
                host_idx = i;
                break;
            }
        }
        if (host_idx == -1) {
            host_idx = num_hosts++;
            strcpy(hosts[host_idx], host);
            last_time[host_idx] = ts;
        } else {
            if (ts < last_time[host_idx]) {
                return 255;
            }
            if (metric_is_null && (ts - last_time[host_idx] > 3600)) {
                return 255;
            }
            last_time[host_idx] = ts;
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/legacy_validator.c -o /app/legacy_validator
    strip /app/legacy_validator

    # Generate corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import json

os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

for i in range(50):
    with open(f"/app/corpus/clean/clean_{i}.jsonl", "w") as f:
        f.write(json.dumps({"host_id": f"H{i}", "timestamp": "2023-01-01T12:00:00Z", "message": "ok", "metric": 1.0}) + "\n")
        f.write(json.dumps({"host_id": f"H{i}", "timestamp": "2023-01-01T12:30:00Z", "message": "ok", "metric": None}) + "\n")

for i in range(16):
    with open(f"/app/corpus/evil/evil_uni_{i}.jsonl", "w") as f:
        f.write('{"host_id": "H1", "timestamp": "2023-01-01T12:00:00Z", "message": "bad \\uD83D space", "metric": 1.0}\n')

for i in range(17):
    with open(f"/app/corpus/evil/evil_time_{i}.jsonl", "w") as f:
        f.write(json.dumps({"host_id": "H1", "timestamp": "2023-01-01T12:00:00Z", "message": "ok", "metric": 1.0}) + "\n")
        f.write(json.dumps({"host_id": "H1", "timestamp": "2023-01-01T11:00:00Z", "message": "ok", "metric": 1.0}) + "\n")

for i in range(17):
    with open(f"/app/corpus/evil/evil_imp_{i}.jsonl", "w") as f:
        f.write(json.dumps({"host_id": "H1", "timestamp": "2023-01-01T12:00:00Z", "message": "ok", "metric": 1.0}) + "\n")
        f.write(json.dumps({"host_id": "H1", "timestamp": "2023-01-01T13:05:00Z", "message": "ok", "metric": None}) + "\n")
EOF
    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
