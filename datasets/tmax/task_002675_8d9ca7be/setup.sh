#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest psutil

    mkdir -p /home/user/sensor_service
    cd /home/user/sensor_service

    cat << 'EOF' > Makefile
all: libsensor.so

# BUG: Missing -fPIC
sensor_lib.o: sensor_lib.c
	gcc -c -Wall -Werror sensor_lib.c

libsensor.so: sensor_lib.o
	gcc -shared -o libsensor.so sensor_lib.o

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > sensor_lib.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// Simulated sensor processing function
// BUG 1: total_size uses int32_t, causing signed overflow when count * size > 2GB
// BUG 2: malloc'd buffer is never freed.
int process_sensor_data(int32_t packet_count, int32_t packet_size) {
    int32_t total_size = packet_count * packet_size;

    if (total_size <= 0) {
        // Due to overflow, total_size might be negative, bypassing this or 
        // passing negative size to malloc, causing massive allocation/segfault.
    }

    uint8_t *buffer = (uint8_t *)malloc(total_size);
    if (buffer == NULL) {
        return -1; // Allocation failed
    }

    // Simulate processing
    for (int32_t i = 0; i < total_size; i += packet_size) {
        buffer[i] = 0xFF; 
    }

    // LEAK: free(buffer); is missing

    return total_size / packet_size; // return number of processed packets
}
EOF

    cat << 'EOF' > service.py
import ctypes
import time
import os

# Load the library
lib = ctypes.CDLL(os.path.join(os.path.dirname(__file__), './libsensor.so'))

def process_data(count, size):
    return lib.process_sensor_data(count, size)

if __name__ == "__main__":
    print("Service started. Waiting for data...")
    # This simulates the service running and leaking memory
    for i in range(100):
        process_data(1000, 1024)
        time.sleep(0.01)

    print("Attempting large batch...")
    # This will cause a segfault due to int32_t overflow (60000 * 50000 = 3,000,000,000 > 2.14GB)
    process_data(60000, 50000)
    print("Done.")
EOF

    chmod +x service.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
