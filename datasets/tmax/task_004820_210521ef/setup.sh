#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
    pip3 install pytest

    mkdir -p /app/sql-parser-c/src
    mkdir -p /app/sql-parser-c/tests
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create sql-parser-c stub
    cat << 'EOF' > /app/sql-parser-c/src/parser.h
#ifndef PARSER_H
#define PARSER_H

int parse_sql(const char* query);

#endif
EOF

    cat << 'EOF' > /app/sql-parser-c/src/parser.c
// #include <stdio.h>
#include "parser.h"

int parse_sql(const char* query) {
    printf("Parsing: %s\n", query);
    return 0;
}
EOF

    cat << 'EOF' > /app/sql-parser-c/tests/test_parser.c
#include "parser.h"
int main() {
    parse_sql("SELECT 1;");
    return 0;
}
EOF

    cat << 'EOF' > /app/sql-parser-c/Makefile
CFLGS = -Wall -Werror

all: libsqlparser.a

libsqlparser.a: src/parser.o
	ar rcs $@ $^

src/parser.o: src/parser.c
	gcc $(CFLAGS) -c $< -o $@

test: tests/test_parser
	./tests/test_parser

tests/test_parser: tests/test_parser.c libsqlparser.a
	gcc $(CFLAGS) $< -L. -lsqlparser -Isrc -o $@

clean:
	rm -f src/*.o *.a tests/test_parser
EOF

    # Generate corpora
    python3 -c '
import os

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

clean_queries = [
    "SELECT id FROM users WHERE active = 1;",
    "SELECT a.name, b.role FROM users a JOIN roles b ON a.role_id = b.id;",
    "WITH cte AS (SELECT * FROM data LIMIT 10) SELECT * FROM cte;",
    "SELECT COUNT(*) FROM logs WHERE timestamp > NOW();",
    "SELECT * FROM products ORDER BY price DESC LIMIT 5;"
]

evil_queries = [
    "SELECT * FROM tableA, tableB;",
    "SELECT a.*, b.* FROM users a CROSS JOIN logs b;",
    "WITH RECURSIVE cte AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM cte) SELECT * FROM cte;",
    "SELECT * FROM orders, customers, products;",
    "WITH RECURSIVE bomb AS (SELECT * FROM users UNION ALL SELECT * FROM bomb) SELECT * FROM bomb;"
]

for i in range(50):
    with open(os.path.join(clean_dir, f"query_{i}.sql"), "w") as f:
        f.write(clean_queries[i % len(clean_queries)])
    with open(os.path.join(evil_dir, f"query_{i}.sql"), "w") as f:
        f.write(evil_queries[i % len(evil_queries)])
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
