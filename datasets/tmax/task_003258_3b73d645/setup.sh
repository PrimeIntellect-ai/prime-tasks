#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/log_filter-1.0.0
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create source files
    cat << 'EOF' > /app/log_filter-1.0.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

extern void process_directory(const char* input_dir, const char* output_dir);

int init_done = 0;

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input_directory> <output_directory>\n", argv[0]);
        return 1;
    }
    // BUG: init_done = 1; is missing
    assert(init_done);
    process_directory(argv[1], argv[2]);
    return 0;
}
EOF

    cat << 'EOF' > /app/log_filter-1.0.0/worker.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <dirent.h>
#include <string.h>
#include <sys/stat.h>

extern int is_valid_log(const char* filepath);

pthread_mutex_t queue_mutex = PTHREAD_MUTEX_INITIALIZER;
char** file_queue = NULL;
int queue_size = 0;
int queue_capacity = 0;
int queue_head = 0;
int queue_tail = 0;

const char* in_dir;
const char* out_dir;

void enqueue(const char* filename) {
    if (queue_size == queue_capacity) {
        queue_capacity = queue_capacity == 0 ? 10 : queue_capacity * 2;
        file_queue = realloc(file_queue, queue_capacity * sizeof(char*));
    }
    file_queue[queue_tail++] = strdup(filename);
    queue_size++;
}

char* dequeue() {
    if (queue_size == 0) return NULL;
    char* file = file_queue[queue_head++];
    queue_size--;
    return file;
}

void* worker_thread(void* arg) {
    while (1) {
        // BUG: mutex locks are commented out
        // pthread_mutex_lock(&queue_mutex);
        char* filename = dequeue();
        // pthread_mutex_unlock(&queue_mutex);

        if (!filename) break;

        char in_path[1024];
        snprintf(in_path, sizeof(in_path), "%s/%s", in_dir, filename);

        if (is_valid_log(in_path)) {
            char out_path[1024];
            snprintf(out_path, sizeof(out_path), "%s/%s", out_dir, filename);

            FILE* fin = fopen(in_path, "rb");
            FILE* fout = fopen(out_path, "wb");
            if (fin && fout) {
                char buffer[4096];
                size_t bytes;
                while ((bytes = fread(buffer, 1, sizeof(buffer), fin)) > 0) {
                    fwrite(buffer, 1, bytes, fout);
                }
            }
            if (fin) fclose(fin);
            if (fout) fclose(fout);
        }
        free(filename);
    }
    return NULL;
}

void process_directory(const char* input_dir, const char* output_dir) {
    in_dir = input_dir;
    out_dir = output_dir;

    DIR* dir = opendir(input_dir);
    if (!dir) return;

    struct dirent* entry;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_type == DT_REG) {
            enqueue(entry->d_name);
        }
    }
    closedir(dir);

    int num_threads = 4;
    pthread_t threads[4];
    for (int i = 0; i < num_threads; i++) {
        pthread_create(&threads[i], NULL, worker_thread, NULL);
    }
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }
}
EOF

    cat << 'EOF' > /app/log_filter-1.0.0/parser.c
#include <stdio.h>
#include <string.h>

int is_valid_log(const char* filepath) {
    FILE* f = fopen(filepath, "r");
    if (!f) return 0;

    char line[2048];
    while (fgets(line, sizeof(line), f)) {
        // BUG: missing length check strlen(line) > 1024

        for (int i = 0; line[i] != '\0'; i++) {
            // BUG: rejects valid whitespace \r, \n, \t
            if ((unsigned char)line[i] < 0x20) {
                fclose(f);
                return 0;
            }
        }
    }
    fclose(f);
    return 1;
}
EOF

    cat << 'EOF' > /app/log_filter-1.0.0/Makefile
CC = gcc
CFLAGS = -pthread -Wall -g

all: log_filter

log_filter: main.c worker.c parser.c
	$(CC) $(CFLAGS) -o log_filter main.c worker.c parser.c

clean:
	rm -f log_filter
EOF

    # Create corpora files
    echo "Valid log line 1\nValid log line 2\twith tab" > /app/corpora/clean/clean1.log
    echo "Another valid log" > /app/corpora/clean/clean2.log

    # Evil 1: long line
    python3 -c "print('A' * 1025)" > /app/corpora/evil/evil1.log
    # Evil 2: null byte
    python3 -c "print('Bad log\x00data')" > /app/corpora/evil/evil2.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
