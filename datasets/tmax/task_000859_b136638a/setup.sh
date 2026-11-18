#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc-dev binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/profiler_repo
    cd /home/user/profiler_repo

    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Step 1: Create the buggy script
    cat << 'EOF' > run_analysis.sh
#!/bin/bash
requests=$1
time_sec=$2
# Buggy formula: divides first, losing precision
rpm=$(( (requests / time_sec) * 60 ))
echo $rpm
EOF
    chmod +x run_analysis.sh

    git add run_analysis.sh
    git commit -m "Initial commit of analysis wrapper"

    # Step 2: Add the secret seed
    cat << 'EOF' > config.txt
# Core Config
PERF_MAGIC_SEED=a9f8b7c6d5e4
MAX_THREADS=8
EOF
    git add config.txt
    git commit -m "Add core config"

    # Step 3: Remove the secret seed
    rm config.txt
    git add config.txt
    git commit -m "Remove sensitive config file"

    # Step 4: Create and compile the binary with the hidden flag
    cat << 'EOF' > analyzer.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // Hidden flag embedded in the binary data section
    const char *hidden_flag = "--dev-xc92k1l8m4n5";

    if (argc > 1 && strcmp(argv[1], hidden_flag) == 0) {
        printf("Deep trace enabled.\n");
    } else {
        printf("Normal mode.\n");
    }
    return 0;
}
EOF

    gcc analyzer.c -o analyzer_bin
    rm analyzer.c

    chmod -R 777 /home/user
