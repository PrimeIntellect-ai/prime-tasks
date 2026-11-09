#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate video
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=25 -pix_fmt yuv420p /app/experiment.mp4

    # Generate metadata.db
    cat << 'EOF' > /app/generate_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/metadata.db')
c = conn.cursor()

c.execute("CREATE TABLE video_frames (id INTEGER PRIMARY KEY, frame_idx INTEGER)")
c.execute("CREATE TABLE detected_objects (obj_id INTEGER PRIMARY KEY, frame_id INTEGER, obj_class TEXT)")
c.execute("CREATE TABLE object_graph (node_a INTEGER, node_b INTEGER)")

classes = ["cell", "bacteria", "virus", "protein"]
obj_id = 1

for frame_idx in range(125):
    frame_id = frame_idx + 1
    c.execute("INSERT INTO video_frames (id, frame_idx) VALUES (?, ?)", (frame_id, frame_idx))

    objs_in_frame = []
    for _ in range(random.randint(0, 5)):
        c.execute("INSERT INTO detected_objects (obj_id, frame_id, obj_class) VALUES (?, ?, ?)", 
                  (obj_id, frame_id, random.choice(classes)))
        objs_in_frame.append(obj_id)
        obj_id += 1

    for i in range(len(objs_in_frame)):
        for j in range(i+1, len(objs_in_frame)):
            if random.random() < 0.3:
                c.execute("INSERT INTO object_graph (node_a, node_b) VALUES (?, ?)", 
                          (objs_in_frame[i], objs_in_frame[j]))

conn.commit()
conn.close()
EOF
    python3 /app/generate_db.py

    # Create oracle
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    char *video_path = argv[1];
    int frame_number = atoi(argv[2]);
    char *entity_class = argv[3];

    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "ffmpeg -i %s -vf \"select=eq(n\\,%d)\" -vframes 1 -f image2pipe -vcodec rawvideo -pix_fmt rgb24 - 2>/dev/null", video_path, frame_number);

    FILE *fp = popen(cmd, "r");
    if (!fp) return 1;

    double total_y = 0;
    int count = 0;
    unsigned char rgb[3];
    while (fread(rgb, 1, 3, fp) == 3) {
        total_y += 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2];
        count++;
    }
    pclose(fp);

    int intensity = count > 0 ? (int)(total_y / count) : 0;

    sqlite3 *db;
    if (sqlite3_open("/app/metadata.db", &db)) return 1;

    char query[2048];
    snprintf(query, sizeof(query), 
        "SELECT DISTINCT linked_id FROM ("
        "SELECT node_b AS linked_id FROM object_graph JOIN detected_objects ON object_graph.node_a = detected_objects.obj_id JOIN video_frames ON detected_objects.frame_id = video_frames.id WHERE video_frames.frame_idx = %d AND detected_objects.obj_class = '%s' "
        "UNION "
        "SELECT node_a AS linked_id FROM object_graph JOIN detected_objects ON object_graph.node_b = detected_objects.obj_id JOIN video_frames ON detected_objects.frame_id = video_frames.id WHERE video_frames.frame_idx = %d AND detected_objects.obj_class = '%s'"
        ") ORDER BY linked_id ASC;", frame_number, entity_class, frame_number, entity_class);

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, NULL) != SQLITE_OK) return 1;

    int linked[10000];
    int linked_count = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        linked[linked_count++] = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    printf("Intensity: %d | Linked Entities: ", intensity);
    if (linked_count == 0) {
        printf("none\n");
    } else {
        for (int i = 0; i < linked_count; i++) {
            printf("%d%s", linked[i], i == linked_count - 1 ? "" : ",");
        }
        printf("\n");
    }

    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle_query_engine -lsqlite3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
