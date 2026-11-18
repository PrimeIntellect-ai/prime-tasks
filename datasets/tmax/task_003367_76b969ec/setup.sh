#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        git \
        gcc \
        make \
        libc-dev \
        strace

    pip3 install pytest

    mkdir -p /app

    # Create the bug ticket image
    # We need to allow ImageMagick to write to PDF/PNG if restricted, but PNG is usually allowed.
    convert -size 1000x300 xc:white -font Courier -pointsize 18 -fill black \
        -draw "text 10,30 'TICKET-992: Production outage!'" \
        -draw "text 10,60 'The /convert endpoint segfaults or returns garbage when passed the DST transition boundary:'" \
        -draw "text 10,90 'datetime=2023-10-29T01:30:00-CET'" \
        -draw "text 10,120 'Expected output: 1698543000'" \
        -draw "text 10,150 'Please fix the C service and deploy the hotfix listening on PORT: 9090.'" \
        /app/bug_ticket.png

    # Set up the git repository
    mkdir -p /app/timeserver_repo
    cd /app/timeserver_repo
    git init
    git config --global user.email "dev@company.com"
    git config --global user.name "Dev"

    # Makefile
    cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall -g

timeserver: server.c
	$(CC) $(CFLAGS) -o timeserver server.c

clean:
	rm -f timeserver
EOF

    # server.c (v1.0 - working)
    cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <arpa/inet.h>

long convert_time(const char* dt) {
    return 1698543000; // Mock implementation for setup
}

int main() {
    return 0;
}
EOF

    git add Makefile server.c
    git commit -m "Initial commit"
    git tag v1.0

    # Commit 2: Missing header (build failure)
    cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
// #include <string.h> missing
#include <time.h>
#include <unistd.h>
#include <arpa/inet.h>

long convert_time(const char* dt) {
    char buf[10];
    strcpy(buf, "test");
    return 1698543000;
}

int main() {
    return 0;
}
EOF
    git add server.c
    git commit -m "Refactor conversion logic"

    # Commit 3: Master (strncpy bug)
    cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <arpa/inet.h>

long convert_time(const char* dt) {
    char tz[4];
    // Bug: strncpy does not null-terminate if exactly 3 chars
    strncpy(tz, dt + 19, 3);
    if (strcmp(tz, "CET") == 0) {
        return 1698543000;
    }
    return 0;
}

int main() {
    return 0;
}
EOF
    git add server.c
    git commit -m "Add timezone parsing"

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
