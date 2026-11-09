#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        libsqlite3-dev \
        tesseract-ocr \
        libtesseract-dev \
        gcc \
        build-essential \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the image with corrupted nodes
    convert -size 300x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 '14, 27, 55, 91'" /app/corrupted_nodes.png

    # Initialize the SQLite database
    sqlite3 /home/user/routing.db <<EOF
CREATE TABLE routes (src INTEGER, dst INTEGER);
INSERT INTO routes VALUES (10, 1), (10, 2), (14, 1), (14, 2), (27, 5), (55, 1), (91, 2);
CREATE INDEX idx_src ON routes(src);
EOF

    # Create and compile the oracle
    cat << 'EOF' > /app/oracle_route_degree.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int src = atoi(argv[1]);
    sqlite3 *db;
    if (sqlite3_open("/home/user/routing.db", &db) != SQLITE_OK) return 1;

    sqlite3_stmt *stmt;
    const char *sql = "SELECT count(*) FROM routes NOT INDEXED WHERE src = ?";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return 1;
    sqlite3_bind_int(stmt, 1, src);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        printf("%d\n", sqlite3_column_int(stmt, 0));
    } else {
        printf("0\n");
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF
    gcc /app/oracle_route_degree.c -o /app/oracle_route_degree -lsqlite3
    chmod +x /app/oracle_route_degree

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
