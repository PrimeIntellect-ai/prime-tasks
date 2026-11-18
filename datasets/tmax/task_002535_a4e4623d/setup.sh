#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create the C source for the artifact_dumper
    cat << 'EOF' > /tmp/artifact_dumper.c
#include <stdio.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main() {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(41337);
    inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);
    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        return 1;
    }
    close(sock);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -static -s /tmp/artifact_dumper.c -o /app/artifact_dumper
    rm /tmp/artifact_dumper.c

    # Generate corpora using python
    python3 -c '
import os
import random

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

clean_contents = [
    "User login successful. SSN: 123-45-6789.",
    "System update completed. No SSN found.",
    "Error processing record for 987-65-4321, retrying.",
    "Data export initiated by admin."
]

evil_contents = [
    "User login failed: <script>alert(1)</script>",
    "Query executed: admin\" --",
    "Invalid input: 1\" OR \"1\"=\"1",
    "Profile updated: <img src=x onerror=alert(1)>"
]

for i in range(50):
    with open(os.path.join(clean_dir, f"clean_{i}.txt"), "w") as f:
        f.write(random.choice(clean_contents))

for i in range(50):
    with open(os.path.join(evil_dir, f"evil_{i}.txt"), "w") as f:
        f.write(random.choice(evil_contents))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
