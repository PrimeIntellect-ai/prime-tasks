#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc build-essential
    pip3 install pytest

    # Configure git to allow commits
    git config --global user.email "admin@example.com"
    git config --global user.name "Admin"

    mkdir -p /home/user/data_pipeline
    cd /home/user/data_pipeline
    git init

    # Commit 1: Initial commit with the secret and the fuzzing bug
    cat << 'EOF' > pipeline.sh
#!/bin/bash
API_KEY="API-9988-SECRET-KEY"
INPUT=$1

if [ "$INPUT" == "XQZQ" ]; then
    echo "FATAL_EXCEPTION: Buffer overflow"
    exit 1
fi
echo "Processing $INPUT"
exit 0
EOF
    chmod +x pipeline.sh

    cat << 'EOF' > payload_decoder.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "NEXUS_CORE_0x9A") == 0) {
        printf("Decoded.\n");
        return 0;
    }
    printf("Access denied.\n");
    return 1;
}
EOF
    gcc payload_decoder.c -o payload_decoder
    rm payload_decoder.c

    git add pipeline.sh payload_decoder
    git commit -m "Initial working pipeline"

    # Commit 2: Remove API Key
    cat << 'EOF' > pipeline.sh
#!/bin/bash
API_KEY=$ENV_API_KEY
INPUT=$1

if [ "$INPUT" == "XQZQ" ]; then
    echo "FATAL_EXCEPTION: Buffer overflow"
    exit 1
fi
echo "Processing $INPUT"
exit 0
EOF
    git add pipeline.sh
    git commit -m "Security: Remove hardcoded API key"

    # Commit 3: Add test script
    cat << 'EOF' > test_pipeline.sh
#!/bin/bash
./pipeline.sh "TEST" > /dev/null 2>&1
EOF
    chmod +x test_pipeline.sh
    git add test_pipeline.sh
    git commit -m "Add automated test script"

    # Commit 4: The bad commit that breaks the pipeline (bisection target)
    cat << 'EOF' > pipeline.sh
#!/bin/bash
API_KEY=$ENV_API_KEY
INPUT=$1

# Bug introduced here
if [ -n "$INPUT" ]; then
    exit 2 # Accidental fail on valid input
fi

if [ "$INPUT" == "XQZQ" ]; then
    echo "FATAL_EXCEPTION: Buffer overflow"
    exit 1
fi
echo "Processing $INPUT"
exit 0
EOF
    git add pipeline.sh
    git commit -m "Refactor input validation logic"

    # Commit 5: Unrelated feature
    echo "# Dummy comment" >> pipeline.sh
    git add pipeline.sh
    git commit -m "Update comments"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
