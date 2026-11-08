#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip flite zip unzip gcc binutils
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    flite -t "The archive password is delta charlie niner" -o /app/voicemail.wav

    # Create dummy C files for binaries
    mkdir -p /tmp/src
    cat << 'EOF' > /tmp/src/mal.c
#include <stdlib.h>
int main() { 
    const char* env = "HTTP_USER_AGENT"; 
    system("date"); 
    return 0; 
}
EOF

    cat << 'EOF' > /tmp/src/ben1.c
#include <stdlib.h>
int main() { 
    system("date"); 
    return 0; 
}
EOF

    cat << 'EOF' > /tmp/src/ben2.c
#include <stdio.h>
int main() { 
    const char* env = "HTTP_USER_AGENT"; 
    printf("%s", env); 
    return 0; 
}
EOF

    # Compile binaries
    mkdir -p /tmp/evidence
    gcc /tmp/src/mal.c -o /tmp/evidence/mal_bin
    gcc /tmp/src/ben1.c -o /tmp/evidence/ben1_bin
    gcc /tmp/src/ben2.c -o /tmp/evidence/ben2_bin

    # Create encrypted zip
    cd /tmp/evidence
    zip -P "delta charlie niner" /app/evidence.zip *

    # Create hidden test directory
    mkdir -p /app/hidden_test
    for i in $(seq 1 50); do cp /tmp/evidence/mal_bin "/app/hidden_test/mal_$i"; done
    for i in $(seq 1 75); do cp /tmp/evidence/ben1_bin "/app/hidden_test/ben1_$i"; done
    for i in $(seq 1 75); do cp /tmp/evidence/ben2_bin "/app/hidden_test/ben2_$i"; done

    # Clean up temp files
    rm -rf /tmp/src /tmp/evidence

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
