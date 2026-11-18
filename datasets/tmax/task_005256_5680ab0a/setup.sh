#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/legacy_tool
    cd /home/user/legacy_tool
    git init
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"

    # Initial commit
    cat << 'EOF' > process.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <filename>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }
    char buffer[256];
    if (fgets(buffer, sizeof(buffer), f)) {
        double val = atof(buffer);
        printf("Processed: %f\n", val * 2.5);
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc process.c -o process
EOF

    cat << 'EOF' > run.sh
#!/bin/bash
./process $1
EOF

    chmod +x build.sh run.sh
    git add process.c build.sh run.sh
    git commit -m "Initial commit"

    # Commit 2: Add test case
    echo "1048576" > "test case.txt"
    git add "test case.txt"
    git commit -m "Add test case"

    # Commit 3: Remove test case
    git rm "test case.txt"
    git commit -m "Clean up test files"

    # Commit 4: Break the build by adding math dependency without updating build.sh
    cat << 'EOF' > process.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <filename>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }
    char buffer[256];
    if (fgets(buffer, sizeof(buffer), f)) {
        double val = atof(buffer);
        printf("Processed: %f\n", sqrt(val));
    }
    fclose(f);
    return 0;
}
EOF
    git add process.c
    git commit -m "Use sqrt for processing"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
