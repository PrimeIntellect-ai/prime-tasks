#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gdb
    pip3 install pytest

    mkdir -p /home/user/uptime_monitor

    cat << 'EOF' > /home/user/uptime_monitor/Makefile
all: libmetrics.so

libmetrics.so: libmetrics.c
	gcc -shared -o libmetrics.so -fPIC libmetrics.c -lpthred

clean:
	rm -f libmetrics.so
EOF

    cat << 'EOF' > /home/user/uptime_monitor/libmetrics.c
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>

pthread_mutex_t lock_a = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t lock_b = PTHREAD_MUTEX_INITIALIZER;

void get_cpu_metrics() {
    pthread_mutex_lock(&lock_a);
    usleep(1000); // Simulate work and encourage race condition
    pthread_mutex_lock(&lock_b);

    // Read metrics...

    pthread_mutex_unlock(&lock_b);
    pthread_mutex_unlock(&lock_a);
}

void get_mem_metrics() {
    pthread_mutex_lock(&lock_b);
    usleep(1000); // Simulate work and encourage race condition
    pthread_mutex_lock(&lock_a);

    // Read metrics...

    pthread_mutex_unlock(&lock_a);
    pthread_mutex_unlock(&lock_b);
}
EOF

    cat << 'EOF' > /home/user/uptime_monitor/agent.py
import ctypes
import threading
import time
import os

# Load the shared library
lib_path = os.path.join(os.path.dirname(__file__), 'libmetrics.so')
try:
    metrics = ctypes.CDLL(lib_path)
except OSError:
    print("Failed to load libmetrics.so. Did you compile it?")
    exit(1)

def query_cpu():
    for _ in range(50):
        metrics.get_cpu_metrics()

def query_mem():
    for _ in range(50):
        metrics.get_mem_metrics()

def main():
    threads = []

    # Spawn multiple threads to hammer the library and trigger the deadlock
    for i in range(10):
        t1 = threading.Thread(target=query_cpu)
        t2 = threading.Thread(target=query_mem)
        threads.extend([t1, t2])
        t1.start()
        t2.start()

    for t in threads:
        t.join()

    print("Successfully completed all monitoring queries.")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/uptime_monitor
    chmod -R 777 /home/user
