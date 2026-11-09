#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/wal.log
SET "system_status" "offline"
SET "error log" "disk full"
SET "admin user" "jane doe"
SET "background task" "running"
SET "system_status" "online"
SET "admin user" "john smith"
EOF

    cat << 'EOF' > /home/user/recover.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <assert.h>

#define MAX_ENTRIES 100
#define MAX_LEN 256

typedef struct {
    char key[MAX_LEN];
    char value[MAX_LEN];
} Entry;

Entry db[MAX_ENTRIES];
int db_size = 0;

// Need a mutex here but it's missing!
// pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

void update_db(const char* key, const char* value) {
    assert(strlen(key) > 0); // Fails if parsing spaces breaks and key is empty

    // Missing lock
    int found = 0;
    for (int i = 0; i < db_size; i++) {
        if (strcmp(db[i].key, key) == 0) {
            strcpy(db[i].value, value);
            found = 1;
            break;
        }
    }
    if (!found) {
        strcpy(db[db_size].key, key);
        strcpy(db[db_size].value, value);
        db_size++;
    }
    // Missing unlock
}

void* process_chunk(void* arg) {
    char** lines = (char**)arg;
    for (int i = 0; i < 3; i++) {
        if (lines[i] == NULL) continue;
        char key[MAX_LEN] = {0};
        char value[MAX_LEN] = {0};

        // BUG: Fails on spaces. Should be "SET \"%[^\"]\" \"%[^\"]\""
        if (sscanf(lines[i], "SET %s %s", key, value) == 2) {
            update_db(key, value);
        }
    }
    return NULL;
}

int compare_entries(const void* a, const void* b) {
    return strcmp(((Entry*)a)->key, ((Entry*)b)->key);
}

int main() {
    char* chunk1[] = {
        "SET \"system_status\" \"offline\"",
        "SET \"error log\" \"disk full\"",
        "SET \"admin user\" \"jane doe\""
    };
    char* chunk2[] = {
        "SET \"background task\" \"running\"",
        "SET \"system_status\" \"online\"",
        "SET \"admin user\" \"john smith\""
    };

    pthread_t t1, t2;
    pthread_create(&t1, NULL, process_chunk, chunk1);
    pthread_create(&t2, NULL, process_chunk, chunk2);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    qsort(db, db_size, sizeof(Entry), compare_entries);

    FILE* f = fopen("/home/user/recovered.txt", "w");
    if (!f) return 1;
    for (int i = 0; i < db_size; i++) {
        fprintf(f, "%s=%s\n", db[i].key, db[i].value);
    }
    fclose(f);

    return 0;
}
EOF

    chmod -R 777 /home/user
