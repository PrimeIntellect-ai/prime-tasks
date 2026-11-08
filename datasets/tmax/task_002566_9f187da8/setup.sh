#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest jsonpatch

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the legacy validator
    cat << 'EOF' > /app/legacy_validator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    if (strncmp(argv[1], "TOK-", 4) != 0) return 1;
    if (strlen(argv[1]) != 12) return 1;

    char *hex_part = argv[1] + 4;
    char *endptr;
    unsigned long value = strtoul(hex_part, &endptr, 16);
    if (*endptr != '\0') return 1;

    if ((value ^ 0xDEADBEEF) % 13 == 0) {
        return 0;
    }
    return 1;
}
EOF
    gcc -O2 /app/legacy_validator.c -o /app/legacy_validator
    strip /app/legacy_validator
    rm /app/legacy_validator.c

    # Generate valid tokens:
    # 0xDEADBEEF ^ 0 = 0xDEADBEEF
    # 0xDEADBEEF ^ 13 = 0xDEADBEE2
    # 0xDEADBEEF ^ 26 = 0xDEADBEF5
    # 0xDEADBEEF ^ 39 = 0xDEADBEC8

    # Create 10 clean files
    for i in $(seq 1 10); do
        cat << EOF > /app/corpus/clean/clean_${i}.json
{
  "auth_token": "TOK-deadbeef",
  "base_record": {
    "user_id": ${i},
    "role": "editor",
    "profile": {
      "status": "active"
    }
  },
  "record_patch": [
    { "op": "replace", "path": "/role", "value": "viewer" }
  ]
}
EOF
    done

    # Create 15 evil files
    # 1-5: Invalid token
    for i in $(seq 1 5); do
        cat << EOF > /app/corpus/evil/evil_token_${i}.json
{
  "auth_token": "TOK-12345678",
  "base_record": {
    "user_id": ${i},
    "role": "editor",
    "profile": { "status": "active" }
  },
  "record_patch": []
}
EOF
    done

    # 6-10: Privilege escalation to admin
    for i in $(seq 6 10); do
        cat << EOF > /app/corpus/evil/evil_admin_${i}.json
{
  "auth_token": "TOK-deadbeef",
  "base_record": {
    "user_id": ${i},
    "role": "editor",
    "profile": { "status": "active" }
  },
  "record_patch": [
    { "op": "replace", "path": "/role", "value": "admin" }
  ]
}
EOF
    done

    # 11-13: Missing fields
    for i in $(seq 11 13); do
        cat << EOF > /app/corpus/evil/evil_missing_${i}.json
{
  "base_record": {
    "user_id": ${i},
    "role": "editor",
    "profile": { "status": "active" }
  },
  "record_patch": []
}
EOF
    done

    # 14-15: Invalid JSON
    for i in $(seq 14 15); do
        cat << EOF > /app/corpus/evil/evil_json_${i}.json
{
  "auth_token": "TOK-deadbeef",
  "base_record": {
    "user_id": ${i},
    "role": "editor"
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
