#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/db_recover.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char key[256];
    long long utc;
    int txid;
    char op[16];
    char val[256];
    int active;
} Entry;

Entry entries[10000];
int num_entries = 0;

int find_or_create(const char* key) {
    for (int i = 0; i < num_entries; i++) {
        if (strcmp(entries[i].key, key) == 0) return i;
    }
    strcpy(entries[num_entries].key, key);
    entries[num_entries].active = 0;
    entries[num_entries].utc = -1LL;
    entries[num_entries].txid = -1;
    return num_entries++;
}

int cmp(const void* a, const void* b) {
    return strcmp(((Entry*)a)->key, ((Entry*)b)->key);
}

int main() {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        char *txid_str = strtok(line, " \t\n");
        if (!txid_str) continue;
        char *ts_str = strtok(NULL, " \t\n");
        char *tz_str = strtok(NULL, " \t\n");
        char *op_str = strtok(NULL, " \t\n");
        char *key_str = strtok(NULL, " \t\n");
        char *val_str = strtok(NULL, " \t\n");

        if (!key_str) continue;

        int txid = atoi(txid_str);
        long long local_ts = atoll(ts_str);

        int sign = (tz_str[0] == '+') ? 1 : -1;
        int hh = (tz_str[1] - '0') * 10 + (tz_str[2] - '0');
        int mm = (tz_str[3] - '0') * 10 + (tz_str[4] - '0');
        long long offset = sign * (hh * 3600 + mm * 60);
        long long utc = local_ts - offset;

        int idx = find_or_create(key_str);
        if (!entries[idx].active || utc > entries[idx].utc || (utc == entries[idx].utc && txid > entries[idx].txid)) {
            entries[idx].utc = utc;
            entries[idx].txid = txid;
            strcpy(entries[idx].op, op_str);
            if (val_str) {
                strcpy(entries[idx].val, val_str);
            } else {
                entries[idx].val[0] = '\0';
            }
            entries[idx].active = 1;
        }
    }

    qsort(entries, num_entries, sizeof(Entry), cmp);

    for (int i = 0; i < num_entries; i++) {
        if (entries[i].active && strcmp(entries[i].op, "SET") == 0) {
            printf("%s=%s\n", entries[i].key, entries[i].val);
        }
    }
    return 0;
}
EOF

    gcc -O2 /tmp/db_recover.c -o /app/db_recover
    strip /app/db_recover
    rm /tmp/db_recover.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
