#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc gdb
    pip3 install pytest

    mkdir -p /home/user/log_pipeline
    mkdir -p /home/user/raw_logs

    # Generate logs
    cat << 'EOF' > /home/user/raw_logs/alpha.log
[2023-11-01T10:00:00Z] [INFO] Connection established from 192.168.1.10
[2023-11-01T10:05:12Z] [DEBUG] User authenticated: USER_PAYLOAD=jdoe_123
[2023-11-01T10:10:05Z] [INFO] Disconnected
EOF

    cat << 'EOF' > /home/user/raw_logs/beta.log
[2023-11-01T09:55:00Z] [INFO] Service started
[2023-11-01T10:08:22Z] [WARN] Rate limit approached for IP 10.0.0.5
[2023-11-01T10:15:33Z] [DEBUG] User authenticated: USER_PAYLOAD=CRASH_TRIGGER_OVERSIZED_PAYLOAD_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
[2023-11-01T10:20:00Z] [INFO] Service shutting down
EOF

    cat << 'EOF' > /home/user/raw_logs/gamma.log
[2023-11-01T10:01:00Z] [INFO] Sync initiated
[2023-11-01T10:06:00Z] [DEBUG] User authenticated: USER_PAYLOAD=admin_user
[2023-11-01T10:11:00Z] [INFO] Sync completed
EOF

    # Setup Git Repo
    cd /home/user/log_pipeline
    git init
    git config user.name "DevOps"
    git config user.email "devops@example.com"

    # Good state
    cat << 'EOF' > log_parser.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        char *payload_ptr = strstr(line, "USER_PAYLOAD=");
        if (payload_ptr) {
            payload_ptr += 13;
            // Safe print
            printf("Found payload: %s", payload_ptr);
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc -g -O0 log_parser.c -o log_parser
EOF
    chmod +x build.sh

    cat << 'EOF' > process.sh
#!/bin/bash
LOG_DIR=$1
cat $LOG_DIR/*.log | ./log_parser > /dev/null
EOF
    chmod +x process.sh

    git add .
    git commit -m "Initial commit: safe log parser"
    git tag v1.0

    # Add dummy commits
    for i in 1 2 3; do
        echo "// Dummy comment $i" >> log_parser.c
        git commit -am "Refactor: clean up comments $i"
    done

    # Bad commit (introduces buffer overflow)
    cat << 'EOF' > log_parser.c
#include <stdio.h>
#include <string.h>

void process_payload(const char *input) {
    char buffer[32];
    // VULNERABILITY: strcpy into fixed buffer
    strcpy(buffer, input);
    printf("Processed: %s\n", buffer);
}

int main(int argc, char *argv[]) {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        char *payload_ptr = strstr(line, "USER_PAYLOAD=");
        if (payload_ptr) {
            payload_ptr += 13;
            process_payload(payload_ptr);
        }
    }
    return 0;
}
EOF
    git commit -am "Feature: extract payload processing to function"

    # More dummy commits
    for i in 4 5 6; do
        echo "// Another dummy comment $i" >> log_parser.c
        git commit -am "Update: add more inline documentation $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
