#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    # Create directories
    mkdir -p /app/tiny-graph-db
    mkdir -p /app/corpora

    # Create tiny-graph-db files
    cat << 'EOF' > /app/tiny-graph-db/main.c
#include <stdio.h>

#ifdef _INVALID_FLAG_
this is a deliberate syntax error
#endif

int main(void) {
    printf("tiny-graph-db version 1.2.0\n");
    return 0;
}
EOF

    cat << 'EOF' > /app/tiny-graph-db/Makefile
CFLAGS = -O2 -D_INVALID_FLAG_=1

all: bin/tiny-graph-db

bin/tiny-graph-db: main.c
	mkdir -p bin
	gcc $(CFLAGS) -o bin/tiny-graph-db main.c

clean:
	rm -rf bin
EOF

    # Create corpora files
    cat << 'EOF' > /app/corpora/evil_queries.txt
MATCH (a)-[*]->(b)
MATCH (n)-[*1..10]->(m)
MATCH (x)-[*..]->(y)
MATCH (p)-[*..6]->(q)
MATCH (a)-[*6..7]->(b)
EOF

    cat << 'EOF' > /app/corpora/clean_queries.txt
MATCH (a)->(b)
MATCH (n)-[*1..3]->(m)
MATCH (x)-[*1..5]->(y)
MATCH (a)-[*5..5]->(b)
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
