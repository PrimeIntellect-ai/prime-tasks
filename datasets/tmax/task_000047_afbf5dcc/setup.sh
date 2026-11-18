#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /app/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    char *url = argv[1];
    char *query = strchr(url, '?');

    char path[2048] = {0};
    if (query) {
        strncpy(path, url, query - url);
    } else {
        strcpy(path, url);
    }

    if (strstr(path, "../") != NULL) return 1;

    if (query) {
        if (strstr(query, "admin=true") != NULL) return 1;

        char qcopy[2048];
        strcpy(qcopy, query + 1);
        char *keys[100];
        int kcount = 0;
        char *token = strtok(qcopy, "&");
        while (token) {
            char *eq = strchr(token, '=');
            if (eq) {
                *eq = '\0';
            }
            for (int i=0; i<kcount; i++) {
                if (strcmp(keys[i], token) == 0) return 1;
            }
            keys[kcount++] = strdup(token);
            token = strtok(NULL, "&");
        }
    }
    return 0;
}
EOF

gcc -o /app/legacy_route_validator /app/validator.c
strip /app/legacy_route_validator
rm /app/validator.c

cat << 'EOF' > /app/corpus/clean/manifest1.json
{
  "service_name": "clean_svc",
  "dependencies": {"a": ["b"], "b": []},
  "schema_migration": "CREATE TABLE test (id INT);",
  "routes": ["/api/v1/ok?user=1&role=user"]
}
EOF

cat << 'EOF' > /app/corpus/evil/manifest_cycle.json
{
  "service_name": "evil_cycle",
  "dependencies": {"a": ["b"], "b": ["a"]},
  "schema_migration": "CREATE TABLE test (id INT);",
  "routes": ["/api/v1/ok"]
}
EOF

cat << 'EOF' > /app/corpus/evil/manifest_drop.json
{
  "service_name": "evil_drop",
  "dependencies": {"a": []},
  "schema_migration": "DROP TABLE test;",
  "routes": ["/api/v1/ok"]
}
EOF

cat << 'EOF' > /app/corpus/evil/manifest_route1.json
{
  "service_name": "evil_route1",
  "dependencies": {"a": []},
  "schema_migration": "CREATE TABLE test (id INT);",
  "routes": ["/api/v1/../ok"]
}
EOF

cat << 'EOF' > /app/corpus/evil/manifest_route2.json
{
  "service_name": "evil_route2",
  "dependencies": {"a": []},
  "schema_migration": "CREATE TABLE test (id INT);",
  "routes": ["/api/v1/ok?admin=true"]
}
EOF

cat << 'EOF' > /app/corpus/evil/manifest_route3.json
{
  "service_name": "evil_route3",
  "dependencies": {"a": []},
  "schema_migration": "CREATE TABLE test (id INT);",
  "routes": ["/api/v1/ok?id=1&id=2"]
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
