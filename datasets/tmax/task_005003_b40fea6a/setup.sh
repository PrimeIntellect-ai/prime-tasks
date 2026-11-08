#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make wget unzip
pip3 install pytest

mkdir -p /app/csv-graph-toolkit
cd /app/csv-graph-toolkit

# Download SQLite amalgamation
wget https://www.sqlite.org/2024/sqlite-amalgamation-3450100.zip
unzip sqlite-amalgamation-3450100.zip
mv sqlite-amalgamation-3450100/sqlite3.c .
mv sqlite-amalgamation-3450100/sqlite3.h .
rm -rf sqlite-amalgamation-3450100*

# Create edges.csv
cat << 'EOF' > edges.csv
A,B
B,C
C,D
D,E
X,Y
Y,Z
EOF

# Create corrupted graph_query.c
cat << 'EOF' > graph_query.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sqlite3.h"

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    sqlite3 *db;
    char *zErrMsg = 0;
    int rc = sqlite3_open(":memory:", &db);
    if (rc) return 1;

    sqlite3_exec(db, "CREATE TABLE edges(source_id TEXT, target_id TEXT);", 0, 0, &zErrMsg);

    FILE *f = fopen("/app/csv-graph-toolkit/edges.csv", "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *src = strtok(line, ",\n");
        char *tgt = strtok(NULL, ",\n");
        if (src && tgt) {
            char sql[512];
            snprintf(sql, sizeof(sql), "INSERT INTO edges VALUES('%s', '%s');", src, tgt);
            sqlite3_exec(db, sql, 0, 0, &zErrMsg);
        }
    }
    fclose(f);

    sqlite3_stmt *stmt;
    const char *sql = "WITH RECURSIVE traverse(id) AS (SELECT target_id FROM edges WHERE source_id = ?1 UNION SELECT edges.target_id FROM edges JOIN traverse ON edges.target_id = traverse.id) SELECT id FROM traverse ORDER BY id;";

    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return 1;

    sqlite3_bind_text(stmt, 1, argv[1], -1, SQLITE_STATIC);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        printf("%s\n", sqlite3_column_text(stmt, 0));
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

# Create broken Makefile
cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-O2
LDFLAGS=
SRCS=graph_query.c
OBJS=$(SRCS:.c=.o)

graph_query: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f graph_query $(OBJS)
EOF

# Create oracle_graph_query.c
cat << 'EOF' > /tmp/oracle_graph_query.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "/app/csv-graph-toolkit/sqlite3.h"

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    sqlite3 *db;
    char *zErrMsg = 0;
    int rc = sqlite3_open(":memory:", &db);
    if (rc) return 1;

    sqlite3_exec(db, "CREATE TABLE edges(source_id TEXT, target_id TEXT);", 0, 0, &zErrMsg);

    FILE *f = fopen("/app/csv-graph-toolkit/edges.csv", "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *src = strtok(line, ",\n");
        char *tgt = strtok(NULL, ",\n");
        if (src && tgt) {
            char sql[512];
            snprintf(sql, sizeof(sql), "INSERT INTO edges VALUES('%s', '%s');", src, tgt);
            sqlite3_exec(db, sql, 0, 0, &zErrMsg);
        }
    }
    fclose(f);

    sqlite3_stmt *stmt;
    const char *sql = "WITH RECURSIVE traverse(id) AS (SELECT target_id FROM edges WHERE source_id = ?1 UNION SELECT edges.target_id FROM edges JOIN traverse ON edges.source_id = traverse.id) SELECT id FROM traverse ORDER BY id;";

    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return 1;

    sqlite3_bind_text(stmt, 1, argv[1], -1, SQLITE_STATIC);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        printf("%s\n", sqlite3_column_text(stmt, 0));
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

# Compile oracle
gcc -O2 -o /usr/local/bin/oracle_graph_query /tmp/oracle_graph_query.c /app/csv-graph-toolkit/sqlite3.c -ldl -lpthread
rm /tmp/oracle_graph_query.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
