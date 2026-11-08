#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3 libsqlite3-dev gcc make patch
    pip3 install pytest numpy

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=10 -c:v libx264 /app/video.mp4

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src

    sqlite3 /home/user/analytics.db "CREATE TABLE frame_stats (id INTEGER PRIMARY KEY, frame_num INTEGER);"
    for i in $(seq 1 10); do
        sqlite3 /home/user/analytics.db "INSERT INTO frame_stats (frame_num) VALUES ($i);"
    done

    cat << 'EOF' > /home/user/src/pgm.h
#ifndef PGM_H
#define PGM_H
#include <stdint.h>
typedef struct {
    int width;
    int height;
    uint8_t *data;
} PGMImage;
PGMImage* read_pgm(const char *filename);
void free_pgm(PGMImage *img);
#endif
EOF

    cat << 'EOF' > /home/user/src/pgm.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pgm.h"

PGMImage* read_pgm(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return NULL;
    char magic[3];
    if (fscanf(f, "%2s\n", magic) != 1) { fclose(f); return NULL; }
    if (strcmp(magic, "P5") != 0) { fclose(f); return NULL; }
    int w, h, maxval;
    if (fscanf(f, "%d %d\n%d\n", &w, &h, &maxval) != 3) { fclose(f); return NULL; }
    PGMImage *img = malloc(sizeof(PGMImage));
    img->width = w;
    img->height = h;
    img->data = malloc(w * h);
    fread(img->data, 1, w * h, f);
    fclose(f);
    return img;
}

void free_pgm(PGMImage *img) {
    if (img) {
        free(img->data);
        free(img);
    }
}
EOF

    cat << 'EOF' > /home/user/src/list.h
#ifndef LIST_H
#define LIST_H
#include "pgm.h"
typedef struct Node {
    PGMImage *img;
    int frame_num;
    struct Node *next;
    struct Node *prev;
} Node;
typedef struct {
    Node *head;
    Node *tail;
} List;
List* create_list();
void append(List *list, PGMImage *img, int frame_num);
void free_list(List *list);
#endif
EOF

    cat << 'EOF' > /home/user/src/list.c
#include <stdlib.h>
#include "list.h"

List* create_list() {
    List *l = malloc(sizeof(List));
    l->head = NULL;
    l->tail = NULL;
    return l;
}

void append(List *list, PGMImage *img, int frame_num) {
    Node *n = malloc(sizeof(Node));
    n->img = img;
    n->frame_num = frame_num;
    n->next = NULL;
    if (!list->head) {
        list->head = n;
        list->tail = n;
    } else {
        list->tail->next = n;
        list->tail = n;
    }
}

void free_list(List *list) {
    Node *curr = list->head;
    while (curr) {
        Node *next = curr->next;
        free_pgm(curr->img);
        free(curr);
        curr = next;
    }
    free(list);
}
EOF

    cat << 'EOF' > /home/user/src/list_fix.patch
--- list.c	2023-10-01 12:00:00.000000000 +0000
+++ list.c	2023-10-01 12:01:00.000000000 +0000
@@ -14,6 +14,7 @@
     n->img = img;
     n->frame_num = frame_num;
     n->next = NULL;
+    n->prev = list->tail;
     if (!list->head) {
         list->head = n;
         list->tail = n;
EOF

    cat << 'EOF' > /home/user/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <sqlite3.h>
#include "pgm.h"
#include "list.h"

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    char *frames_dir = argv[1];
    char *db_path = argv[2];

    List *frames = create_list();
    for (int i = 1; i <= 10; i++) {
        char path[256];
        sprintf(path, "%s/%04d.pgm", frames_dir, i);
        PGMImage *img = read_pgm(path);
        if (img) append(frames, img, i);
    }

    sqlite3 *db;
    sqlite3_open(db_path, &db);

    Node *curr = frames->head;
    while (curr && curr->next) {
        PGMImage *img1 = curr->img;
        PGMImage *img2 = curr->next->img;
        double mad = 0;
        int pixels = img1->width * img1->height;
        // BUG: out of bounds access
        for (int i = 0; i <= pixels; i++) {
            mad += abs(img1->data[i] - img2->data[i]);
        }
        mad /= pixels;

        char sql[256];
        sprintf(sql, "UPDATE frame_stats SET diff_score = %f, timestamp_ms = %d WHERE frame_num = %d", mad, (curr->next->frame_num - 1) * 100, curr->next->frame_num);
        sqlite3_exec(db, sql, 0, 0, 0);

        curr = curr->next;
    }

    sqlite3_close(db);
    free_list(frames);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
all:
gcc -o motion_analyzer main.c pgm.c list.c
EOF

    chmod -R 777 /home/user
