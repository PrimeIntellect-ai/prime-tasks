#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[4096];
    if (!fgets(line, sizeof(line), stdin)) return 0;

    char id[256] = "";
    char ts[256] = "";
    float t = -999.0, h = -999.0, p = -999.0;
    int t_set = 0, h_set = 0, p_set = 0;

    char *id_start = strstr(line, "[ID:");
    if (id_start) {
        sscanf(id_start, "[ID:%255[^]]]", id);
    }

    char *ts_start = id_start ? strchr(id_start, ']') : NULL;
    if (ts_start) {
        ts_start = strchr(ts_start, '[');
        if (ts_start) {
            sscanf(ts_start, "[%255[^]]]", ts);
        }
    }

    char *data_start = strstr(line, "DATA: ");
    if (data_start) {
        data_start += 6;
        char *token = strtok(data_start, ";\n");
        while (token) {
            char k;
            float v;
            if (sscanf(token, " %c=%f", &k, &v) == 2) {
                if (k == 'T') { t = v; t_set = 1; }
                else if (k == 'H') { h = v; h_set = 1; }
                else if (k == 'P') { p = v; p_set = 1; }
            }
            token = strtok(NULL, ";\n");
        }
    }

    if (!t_set || t <= -50.0 || t >= 80.0) t = 0.0;
    if (!h_set || h < 0.0 || h > 100.0) h = 50.0;
    if (!p_set || p < 900.0 || p > 1100.0) p = 1000.0;

    printf("%s|%s|%.1f|%.1f|%.1f\n", id, ts, t, h, p);
    return 0;
}
EOF

    gcc -O2 /app/legacy_processor.c -o /app/legacy_processor
    strip /app/legacy_processor
    rm /app/legacy_processor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
