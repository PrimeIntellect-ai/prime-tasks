#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc espeak
    pip3 install pytest

    mkdir -p /app

    # Generate audio instructions
    espeak -w /app/audit_instructions.wav "To calculate the risk score, you must compute the average price of the three most recent trades for each symbol, ordered by timestamp descending. Because the index on the symbol column is corrupted, you must append the NOT INDEXED clause to your queries to force a full table scan, otherwise you will read stale ghost rows."

    # Create database
    sqlite3 /app/trading.db <<EOF
CREATE TABLE trades (id INTEGER PRIMARY KEY, symbol TEXT, price REAL, volume INTEGER, timestamp DATETIME);
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('AAPL', 150.0, 100, '2023-01-01 10:00:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('AAPL', 151.0, 100, '2023-01-01 10:01:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('AAPL', 152.0, 100, '2023-01-01 10:02:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('GOOG', 2800.0, 50, '2023-01-01 10:00:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('GOOG', 2801.0, 50, '2023-01-01 10:01:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('GOOG', 2802.0, 50, '2023-01-01 10:02:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('MSFT', 300.0, 200, '2023-01-01 10:00:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('MSFT', 305.0, 200, '2023-01-01 10:01:00');
INSERT INTO trades (symbol, price, volume, timestamp) VALUES ('MSFT', 310.0, 200, '2023-01-01 10:02:00');
CREATE INDEX idx_symbol ON trades(symbol);
EOF

    # Create oracle C program
    cat <<'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

int compare_strings(const void *a, const void *b) {
    return strcmp(*(const char **)a, *(const char **)b);
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    sqlite3 *db;
    if (sqlite3_open("/app/trading.db", &db) != SQLITE_OK) return 1;

    char *input = strdup(argv[1]);
    char *symbols[100];
    int count = 0;
    char *token = strtok(input, ",");
    while (token && count < 100) {
        symbols[count++] = token;
        token = strtok(NULL, ",");
    }
    qsort(symbols, count, sizeof(char *), compare_strings);

    printf("[");
    for (int i = 0; i < count; i++) {
        sqlite3_stmt *stmt;
        const char *sql = "SELECT AVG(price) FROM (SELECT price FROM trades NOT INDEXED WHERE symbol = ? ORDER BY timestamp DESC LIMIT 3)";
        sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        sqlite3_bind_text(stmt, 1, symbols[i], -1, SQLITE_STATIC);
        double score = 0.0;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            score = sqlite3_column_double(stmt, 0);
        }
        sqlite3_finalize(stmt);
        if (i > 0) printf(",");
        printf("{\"symbol\":\"%s\",\"risk_score\":%.2f}", symbols[i], score);
    }
    printf("]");
    sqlite3_close(db);
    free(input);
    return 0;
}
EOF

    gcc /app/oracle.c -o /app/oracle_auditor -lsqlite3
    chmod +x /app/oracle_auditor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
