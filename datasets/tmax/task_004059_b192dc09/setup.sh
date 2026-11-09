#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc file coreutils binutils
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Create and compile the log_parser binary
    cat << 'EOF' > /app/parser.c
#include <stdio.h>
#include <string.h>

int main() {
    unsigned char buf[8192];
    size_t n = fread(buf, 1, sizeof(buf), stdin);
    for (size_t i = 0; i + 3 < n; i++) {
        if (buf[i] == 0xDE && buf[i+1] == 0xAD && buf[i+2] == 0xBE && buf[i+3] == 0xEF) {
            int *p = NULL;
            *p = 1; // Intentional crash
        }
    }
    return 0;
}
EOF
    gcc -O2 -o /app/log_parser /app/parser.c
    strip /app/log_parser
    rm /app/parser.c

    # Generate the git repository with 200 commits
    mkdir -p /home/user/pipeline
    cd /home/user/pipeline
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    for i in $(seq 1 200); do
        echo "#!/bin/bash" > generate_payload.sh
        echo "echo 'Payload generator version $i'" >> generate_payload.sh
        if [ $i -ge 137 ]; then
            echo "printf '\xDE\xAD\xBE\xEF'" >> generate_payload.sh
        fi
        chmod +x generate_payload.sh
        git add generate_payload.sh
        git commit -m "Update payload generator: commit $i"
    done

    # Generate the corpus
    mkdir -p /app/corpus/evil /app/corpus/clean
    for i in $(seq 1 50); do
        # Clean files
        head -c 64 /dev/urandom > /app/corpus/clean/payload_$i.bin

        # Evil files
        head -c 32 /dev/urandom > /app/corpus/evil/payload_$i.bin
        printf "\xDE\xAD\xBE\xEF" >> /app/corpus/evil/payload_$i.bin
        head -c 32 /dev/urandom >> /app/corpus/evil/payload_$i.bin
    done

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure permissions are correct
    chmod -R 777 /home/user
