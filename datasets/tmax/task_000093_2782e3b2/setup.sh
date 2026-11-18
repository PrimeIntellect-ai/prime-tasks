#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /app/
mkdir -p /home/user/logs/

# Create the legacy processor source
cat << 'EOF' > /tmp/legacy_processor.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    char buffer[1024];
    // Disable buffering
    setvbuf(stdout, NULL, _IONBF, 0);

    while (fgets(buffer, sizeof(buffer), stdin)) {
        if (strstr(buffer, "POISON_PILL") != NULL) {
            abort(); // Simulate crash
        }
        // Simulate expensive work (10ms)
        usleep(10000);
        printf("PROCESSED: %s", buffer);
    }
    return 0;
}
EOF

# Compile as a stripped binary
gcc -O3 -s /tmp/legacy_processor.c -o /app/legacy_processor
chmod +x /app/legacy_processor

# Generate test data (2000 lines, 10 poison pills)
python3 -c '
import random
random.seed(42)
with open("/app/test_data.txt", "w") as f:
    for i in range(2000):
        if random.random() < 0.005:
            f.write(f"LINE {i} - POISON_PILL\n")
        else:
            # Pad lines to ensure log rotation triggers during test (approx 600 bytes per line)
            padding = "A" * 550
            f.write(f"LINE {i} - {padding}\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
