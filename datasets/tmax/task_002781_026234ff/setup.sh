#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create dummy query_oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[4096];
    size_t len = fread(buffer, 1, sizeof(buffer)-1, stdin);
    buffer[len] = '\0';
    if (strstr(buffer, "DROP") || strstr(buffer, "DELETE")) {
        printf("UNSAFE\n");
    } else {
        printf("SAFE\n");
    }
    return 0;
}
EOF
    gcc -o /app/query_oracle /tmp/oracle.c
    strip -s /app/query_oracle
    rm /tmp/oracle.c

    # Create corpus files
    for i in $(seq 1 50); do
        echo "SELECT * FROM table1 t1 INNER JOIN table2 t2 ON t1.id = t2.id WHERE t1.val = $i;" > /app/corpus/clean/clean_${i}.sql
        echo "SELECT * FROM table1 CROSS JOIN table2;" > /app/corpus/evil/evil_${i}.sql
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
