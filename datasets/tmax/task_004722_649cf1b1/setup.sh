#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc libsqlite3-dev
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create the verifier script
    cat << 'EOF' > /app/verify.py
import pandas as pd
import sqlite3
from sklearn.metrics import f1_score

def get_ground_truth():
    conn = sqlite3.connect('/home/user/backups.sqlite')
    query = """
    WITH NewerStats AS (
        SELECT 
            chunk_id,
            is_encrypted,
            chunk_size,
            COUNT(*) OVER w as newer_count,
            SUM(chunk_size) OVER w as newer_sum_size
        FROM chunks
        WINDOW w AS (
            PARTITION BY server_id, file_path_hash 
            ORDER BY timestamp DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        )
    )
    SELECT chunk_id FROM NewerStats 
    WHERE is_encrypted = 0 
      AND newer_count >= 3 
      AND newer_sum_size > (2.5 * chunk_size)
    """
    df = pd.read_sql_query(query, conn)
    return set(df['chunk_id'])

def verify():
    try:
        agent_df = pd.read_csv('/home/user/obsolete_chunks.csv')
        agent_set = set(agent_df['chunk_id'])
    except Exception:
        agent_set = set()

    gt_set = get_ground_truth()

    # Calculate F1
    all_items = gt_set.union(agent_set)
    if not all_items:
        print("F1=1.0")
        return 1.0

    y_true = [1 if x in gt_set else 0 for x in all_items]
    y_pred = [1 if x in agent_set else 0 for x in all_items]

    score = f1_score(y_true, y_pred)
    print(f"F1={score}")
    return score

if __name__ == '__main__':
    verify()
EOF

    # Create C source for the oracle binary
    cat << 'EOF' > /app/retention_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc != 7) return 1;
    long long chunk_id = atoll(argv[1]);
    long long server_id = atoll(argv[2]);
    char *file_path_hash = argv[3];
    long long timestamp = atoll(argv[4]);
    long long chunk_size = atoll(argv[5]);
    int is_encrypted = atoi(argv[6]);

    if (is_encrypted != 0) {
        printf("0\n");
        return 0;
    }

    sqlite3 *db;
    if (sqlite3_open("/home/user/backups.sqlite", &db)) {
        return 1;
    }

    char query[1024];
    snprintf(query, sizeof(query),
        "SELECT COUNT(*), SUM(chunk_size) FROM chunks "
        "WHERE server_id = %lld AND file_path_hash = '%s' AND timestamp > %lld",
        server_id, file_path_hash, timestamp);

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, NULL) != SQLITE_OK) {
        return 1;
    }

    int obsolete = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        long long count = sqlite3_column_int64(stmt, 0);
        long long sum_size = sqlite3_column_int64(stmt, 1);
        if (count >= 3 && sum_size > 2.5 * chunk_size) {
            obsolete = 1;
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    usleep(10000); // 0.01 seconds artificial delay
    printf("%d\n", obsolete);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 -o /app/retention_oracle /app/retention_oracle.c -lsqlite3
    strip /app/retention_oracle
    rm /app/retention_oracle.c

    # Create the database generator script
    cat << 'EOF' > /app/generate_db.py
import sqlite3
import random
import hashlib

conn = sqlite3.connect('/home/user/backups.sqlite')
c = conn.cursor()
c.execute("CREATE TABLE servers (server_id INTEGER PRIMARY KEY, hostname TEXT);")
c.execute("CREATE TABLE files (file_path_hash TEXT PRIMARY KEY, original_path TEXT);")
c.execute("""CREATE TABLE chunks (
    chunk_id INTEGER PRIMARY KEY,
    server_id INTEGER,
    file_path_hash TEXT,
    timestamp INTEGER,
    chunk_size INTEGER,
    is_encrypted INTEGER
);""")

servers = [(i, f"server-{i}") for i in range(1, 1001)]
c.executemany("INSERT INTO servers VALUES (?, ?)", servers)

files = []
for i in range(5000):
    path = f"/data/file_{i}.dat"
    h = hashlib.md5(path.encode()).hexdigest()
    files.append((h, path))
c.executemany("INSERT INTO files VALUES (?, ?)", files)

chunks = []
chunk_id = 1
for _ in range(251000):
    server_id = random.randint(1, 1000)
    file_hash = random.choice(files)[0]
    timestamp = random.randint(1600000000, 1700000000)
    chunk_size = random.randint(1000, 1000000)
    is_encrypted = random.choices([0, 1], weights=[0.9, 0.1])[0]
    chunks.append((chunk_id, server_id, file_hash, timestamp, chunk_size, is_encrypted))
    chunk_id += 1

c.executemany("INSERT INTO chunks VALUES (?, ?, ?, ?, ?, ?)", chunks)
conn.commit()
conn.close()
EOF

    # Generate the database
    python3 /app/generate_db.py
    rm /app/generate_db.py

    # Set permissions
    chmod -R 777 /home/user
