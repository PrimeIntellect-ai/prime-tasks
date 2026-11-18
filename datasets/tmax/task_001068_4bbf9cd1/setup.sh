#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/telemetry_app/data

cat << 'EOF' > /home/user/telemetry_app/telemetry_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include <dirent.h>

int global_records_processed = 0;
// Mutex intentionally missing for task

void* process_file(void* arg) {
    char* filename = (char*)arg;
    FILE* f = fopen(filename, "r");
    if (!f) {
        free(filename);
        return NULL;
    }

    char buffer[128];
    // Bug 1: Buffer overflow risk
    while (fscanf(f, "%s", buffer) == 1) {
        char *ptr = buffer;

        // Bug 2: Infinite loop if string contains '#'
        while (*ptr != '\0') {
            if (*ptr == '#') {
                continue; // Missing ptr++ causes infinite loop
            }
            ptr++;
        }

        // Bug 3: Race condition
        global_records_processed++;
    }
    fclose(f);
    free(filename);
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <data_directory>\n", argv[0]);
        return 1;
    }

    DIR *d;
    struct dirent *dir;
    d = opendir(argv[1]);
    if (!d) {
        perror("opendir");
        return 1;
    }

    pthread_t threads[200];
    int thread_count = 0;

    while ((dir = readdir(d)) != NULL) {
        if (dir->d_type == DT_REG) {
            char *filepath = malloc(512);
            snprintf(filepath, 512, "%s/%s", argv[1], dir->d_name);
            pthread_create(&threads[thread_count++], NULL, process_file, filepath);
        }
    }
    closedir(d);

    for (int i = 0; i < thread_count; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("Total records: %d\n", global_records_processed);
    return 0;
}
EOF

cat << 'EOF' > /home/user/telemetry_app/generate_data.py
import os

data_dir = "/home/user/telemetry_app/data"
os.makedirs(data_dir, exist_ok=True)

for i in range(1, 51):
    filepath = os.path.join(data_dir, f"log_{i:03d}.txt")
    with open(filepath, "w") as f:
        words = ["record"] * 100

        if i == 10:
            words[50] = "record#with#hash" # Triggers infinite loop
        elif i == 20:
            words[75] = "A" * 200 # Triggers buffer overflow

        f.write(" ".join(words))
EOF

python3 /home/user/telemetry_app/generate_data.py

chmod -R 777 /home/user
