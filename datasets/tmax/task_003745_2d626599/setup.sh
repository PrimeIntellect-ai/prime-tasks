#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb strace ltrace binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>

typedef struct {
    long long ts;
    char ts_str[11];
    char lvl[32];
    char *line;
    int original_order;
} LogEntry;

int compare(const void *a, const void *b) {
    LogEntry *ea = (LogEntry *)a;
    LogEntry *eb = (LogEntry *)b;
    if (ea->ts < eb->ts) return -1;
    if (ea->ts > eb->ts) return 1;
    return ea->original_order - eb->original_order;
}

int main() {
    char *line = NULL;
    size_t len = 0;
    ssize_t read;
    LogEntry *entries = NULL;
    int capacity = 1000;
    int count = 0;
    entries = malloc(capacity * sizeof(LogEntry));

    regex_t regex_ts, regex_lvl;
    regcomp(&regex_ts, "ts=([0-9]{10})", REG_EXTENDED);
    regcomp(&regex_lvl, "lvl=([A-Z]+)", REG_EXTENDED);

    while ((read = getline(&line, &len, stdin)) != -1) {
        if (strstr(line, "TRACE") != NULL) continue;

        if (read > 0 && line[read-1] == '\n') {
            line[read-1] = '\0';
        }

        regmatch_t matches[2];
        char ts_str[11] = "0000000000";
        char lvl_str[32] = "INFO";
        long long ts_val = 0;

        if (regexec(&regex_ts, line, 2, matches, 0) == 0) {
            int match_len = matches[1].rm_eo - matches[1].rm_so;
            if (match_len == 10) {
                strncpy(ts_str, line + matches[1].rm_so, 10);
                ts_str[10] = '\0';
                ts_val = atoll(ts_str);
            }
        }

        if (regexec(&regex_lvl, line, 2, matches, 0) == 0) {
            int match_len = matches[1].rm_eo - matches[1].rm_so;
            if (match_len < 31) {
                strncpy(lvl_str, line + matches[1].rm_so, match_len);
                lvl_str[match_len] = '\0';
            }
        }

        if (count >= capacity) {
            capacity *= 2;
            entries = realloc(entries, capacity * sizeof(LogEntry));
        }

        entries[count].ts = ts_val;
        strcpy(entries[count].ts_str, ts_str);
        strcpy(entries[count].lvl, lvl_str);
        entries[count].line = strdup(line);
        entries[count].original_order = count;
        count++;
    }

    qsort(entries, count, sizeof(LogEntry), compare);

    for (int i = 0; i < count; i++) {
        printf("%s\t%s\t%s\n", entries[i].ts_str, entries[i].lvl, entries[i].line);
        free(entries[i].line);
    }

    free(entries);
    free(line);
    regfree(&regex_ts);
    regfree(&regex_lvl);
    return 0;
}
EOF

    gcc -O2 /tmp/aggregator.c -o /app/log_aggregator
    strip /app/log_aggregator
    rm /tmp/aggregator.c

    # Create a fake core dump
    dd if=/dev/urandom of=/app/aggregator.core bs=1M count=10 2>/dev/null

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
