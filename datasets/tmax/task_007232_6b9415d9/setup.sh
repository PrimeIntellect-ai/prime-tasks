#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc binutils strace ltrace
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 data.db <<EOF
CREATE TABLE metrics (id INTEGER PRIMARY KEY, status INTEGER, payload TEXT);
INSERT INTO metrics (id, status, payload) VALUES (1, 0, 'inactive_data');
INSERT INTO metrics (id, status, payload) VALUES (2, 1, 'cGVyZl9tZXRyaWNfYXBwXzEyOTg=');
INSERT INTO metrics (id, status, payload) VALUES (3, 1, 'Y3B1X3VzYWdlXzEwMF9wZXJjZW50');
EOF

    # Create C program for the binary
    cat << 'EOF' > bin_reader.c
#include <stdio.h>
#include <string.h>

void decode_base64(const char *input) {
    if (strcmp(input, "cGVyZl9tZXRyaWNfYXBwXzEyOTg=") == 0) {
        printf("perf_metric_app_1298\n");
    } else if (strcmp(input, "Y3B1X3VzYWdlXzEwMF9wZXJjZW50") == 0) {
        printf("cpu_usage_100_percent\n");
    } else {
        printf("Error: invalid payload format\n");
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s [flag] <payload>\n", argv[0]);
        return 1;
    }

    // Hidden flag is --x-decode-v2
    if (strcmp(argv[1], "--x-decode-v2") == 0 && argc == 3) {
        decode_base64(argv[2]);
        return 0;
    } else {
        printf("Error: missing or invalid parameters. Decoder failed.\n");
        return 1;
    }
}
EOF

    # Compile and strip
    gcc -O2 bin_reader.c -o bin_reader
    strip bin_reader
    rm bin_reader.c

    # Create the buggy Bash script
    cat << 'EOF' > run_profiler.sh
#!/bin/bash

DB_FILE="/home/user/data.db"

process_payload() {
    local payload=$1
    local attempt=$2

    # Bug 1: Missing attempt limit check for base case
    # Bug 3: Missing hidden flag for bin_reader
    local result=$(/home/user/bin_reader "$payload")

    if [[ "$result" == *"Error"* ]]; then
        # Infinite recursion here
        process_payload "$payload" $((attempt + 1))
    else
        echo "$result"
    fi
}

# Bug 2: Querying status='active' instead of status=1
payloads=$(sqlite3 "$DB_FILE" "SELECT payload FROM metrics WHERE status = 'active';")

for p in $payloads; do
    process_payload "$p" 0
done
EOF
    chmod +x run_profiler.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
