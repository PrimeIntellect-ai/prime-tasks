#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    mkdir -p /data /app /home/user/configs

    python3 -c '
import sqlite3, random
conn = sqlite3.connect("/data/configs.db")
c = conn.cursor()
c.execute("CREATE TABLE snapshots (id INTEGER PRIMARY KEY, content TEXT)")
base_config = {"host": "127.0.0.1", "port": "8080", "db_password": "init", "timeout": "30", "api_token": "abc"}
for i in range(1, 2001):
    if random.random() < 0.1: base_config["port"] = str(random.randint(8000, 9000))
    if random.random() < 0.1: base_config["db_password"] = f"pass{i}"
    if random.random() < 0.05 and "user" in base_config: del base_config["user"]
    elif random.random() < 0.05: base_config["user"] = f"user{i}"
    content = "\n".join(f"{k}={v}" for k, v in base_config.items()) + "\n"
    c.execute("INSERT INTO snapshots (id, content) VALUES (?, ?)", (i, content))
conn.commit()
'

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_KEYS 1000
#define MAX_LEN 256

typedef struct {
    char key[MAX_LEN];
    char val[MAX_LEN];
} KV;

int is_sensitive(const char* key) {
    char lower[256];
    for(int i=0; key[i] && i<255; i++) lower[i] = tolower(key[i]);
    lower[255] = 0;
    if(strstr(lower, "secret") || strstr(lower, "password") || strstr(lower, "token")) return 1;
    return 0;
}

int read_kvs(const char* filename, KV* kvs) {
    FILE* f = fopen(filename, "r");
    if(!f) return 0;
    char line[512];
    int count = 0;
    while(fgets(line, sizeof(line), f)) {
        char* eq = strchr(line, '=');
        if(eq) {
            *eq = 0;
            strcpy(kvs[count].key, line);
            char* val = eq + 1;
            char* nl = strchr(val, '\n');
            if(nl) *nl = 0;
            strcpy(kvs[count].val, val);
            count++;
        }
    }
    fclose(f);
    return count;
}

int main(int argc, char** argv) {
    if(argc != 3) return 1;
    KV kv1[MAX_KEYS];
    KV kv2[MAX_KEYS];
    int c1 = read_kvs(argv[1], kv1);
    int c2 = read_kvs(argv[2], kv2);

    int added = 0, removed = 0, modified = 0, secrets = 0;

    for(int i=0; i<c2; i++) {
        int found = 0;
        for(int j=0; j<c1; j++) {
            if(strcmp(kv2[i].key, kv1[j].key) == 0) {
                found = 1;
                if(strcmp(kv2[i].val, kv1[j].val) != 0) {
                    if(is_sensitive(kv2[i].key)) secrets++;
                    else modified++;
                }
                break;
            }
        }
        if(!found) {
            if(is_sensitive(kv2[i].key)) secrets++;
            else added++;
        }
    }

    for(int i=0; i<c1; i++) {
        int found = 0;
        for(int j=0; j<c2; j++) {
            if(strcmp(kv1[i].key, kv2[j].key) == 0) {
                found = 1;
                break;
            }
        }
        if(!found) {
            if(is_sensitive(kv1[i].key)) secrets++;
            else removed++;
        }
    }

    printf("%s -> %s: added: %d, removed: %d, modified: %d, secrets_masked: %d\n", argv[1], argv[2], added, removed, modified, secrets);
    return 0;
}
EOF

    gcc -O3 /tmp/oracle.c -o /app/config_diff_oracle
    strip /app/config_diff_oracle
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
