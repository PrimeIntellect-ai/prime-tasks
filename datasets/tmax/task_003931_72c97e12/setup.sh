#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/process_chunk.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 3) return 1;
    char* filename = argv[1];
    char* text = argv[2];
    FILE *f;
    int safe = (getenv("FORCE_SAFE_LOGGING_99") != NULL);

    if (safe) {
        f = fopen(filename, "a");
        fprintf(f, "%s\n", text);
        fclose(f);
    } else {
        f = fopen(filename, "a");
        for (int i=0; i<strlen(text); i++) {
            fputc(text[i], f);
            usleep(100); // Induce race condition
        }
        fputc('\n', f);
        fclose(f);
    }
    return 0;
}
EOF

    gcc /home/user/process_chunk.c -o /home/user/process_chunk.bin
    rm /home/user/process_chunk.c

    cat << 'EOF' > /home/user/aggregator.py
import threading
import subprocess
import os

def run_worker(text):
    # Bug: Not passing env vars and not using the safe environment variable
    subprocess.run(["/home/user/process_chunk.bin", "/home/user/output.log", text])

threads = []
for i in range(10):
    t = threading.Thread(target=run_worker, args=(f"Line_data_from_worker_{i}",))
    threads.append(t)
    t.start()

for t in threads:
    t.join()
EOF

    chmod -R 777 /home/user
