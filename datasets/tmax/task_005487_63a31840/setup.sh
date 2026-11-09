#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/ci

    cat << 'EOF' > /home/user/project/src/expr.c
#include <stdio.h>
#include <stdlib.h>

// BUG: Visibility is hidden, preventing the CLI from linking correctly.
__attribute__((visibility("hidden"))) int evaluate_math(const char* expr) {
    // Simple implementation utilizing a system call for the sake of the mock
    char command[256];
    snprintf(command, sizeof(command), "echo '%s' | bc", expr);
    FILE* fp = popen(command, "r");
    if (!fp) return 0;
    int result = 0;
    fscanf(fp, "%d", &result);
    pclose(fp);
    return result;
}
EOF

    cat << 'EOF' > /home/user/project/src/cli.c
#include <stdio.h>

// Declaration of the external function
extern int evaluate_math(const char* expr);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    int result = evaluate_math(argv[1]);
    printf("%d\n", result);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/ci/run_pipeline.sh
#!/bin/bash

cd /home/user/project

# Phase 1: Build the shared library (BUG: missing -fPIC and -shared flags)
gcc -o libexpr.so src/expr.c

# Phase 2: Build the CLI (BUG: Needs to link against libexpr.so with proper RPATH)
gcc src/cli.c -o expr_cli -L. -lexpr

# Phase 3: Testing
EXPRESSIONS=(
    "4 + 5"
    "10 * 2 - 3"
    "100 / 4 + 7"
)

for expr in "${EXPRESSIONS[@]}"; do
    # BUG: Expected calculation is broken. This just returns 0.
    EXPECTED=$(echo "0")

    # Run CLI
    ACTUAL=$(LD_LIBRARY_PATH=. ./expr_cli "$expr")

    if [ "$ACTUAL" != "$EXPECTED" ]; then
        echo "Test failed for '$expr': expected $EXPECTED, got $ACTUAL"
        exit 1
    fi
done

# Success
echo "PIPELINE_SUCCESS" > /home/user/pipeline_status.txt
EOF

    chmod +x /home/user/project/ci/run_pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
