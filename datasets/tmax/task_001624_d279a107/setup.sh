#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y ffmpeg libsqlite3-dev build-essential gcc libgl1 libglib2.0-0
    pip3 install opencv-python numpy

    mkdir -p /app
    cat << 'EOF' > /app/make_vid.py
import cv2
import numpy as np
import random

random.seed(42)
out = cv2.VideoWriter('/app/graph.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))

for frame_idx in range(1, 301):
    src = random.randint(0, 20)
    dst = random.randint(0, 20)
    weight = random.randint(1, 50)

    img = np.zeros((64, 64, 3), dtype=np.uint8)
    img[:, :] = [weight, dst, src] # BGR format for cv2
    out.write(img)

out.release()
EOF
    python3 /app/make_vid.py

    cat << 'EOF' > /app/oracle_query.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    int start_node = atoi(argv[1]);
    int end_node = atoi(argv[2]);

    sqlite3 *db;
    if (sqlite3_open("/home/user/graph.db", &db) != SQLITE_OK) return 1;

    const char *query = 
        "WITH RECURSIVE paths(end_node, total_weight, last_frame, path_frames) AS ("
        "  SELECT dst, weight, frame, CAST(frame AS TEXT) "
        "  FROM edges WHERE src = ? "
        "  UNION ALL "
        "  SELECT e.dst, p.total_weight + e.weight, e.frame, p.path_frames || ',' || CAST(e.frame AS TEXT) "
        "  FROM paths p JOIN edges e ON p.end_node = e.src "
        "  WHERE e.frame > p.last_frame"
        ") "
        "SELECT total_weight, path_frames FROM paths "
        "WHERE end_node = ? "
        "ORDER BY total_weight ASC, last_frame ASC LIMIT 1;";

    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, query, -1, &stmt, NULL);
    sqlite3_bind_int(stmt, 1, start_node);
    sqlite3_bind_int(stmt, 2, end_node);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        printf("Weight: %d, Frames: %s\n", sqlite3_column_int(stmt, 0), sqlite3_column_text(stmt, 1));
    } else {
        printf("No path\n");
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF
    gcc -O3 /app/oracle_query.c -o /app/oracle_query -lsqlite3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
