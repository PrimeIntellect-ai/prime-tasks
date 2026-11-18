#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    mkdir -p /home/user/pipeline/tools /home/user/pipeline/scripts /home/user/project

    cat << 'EOF' > /home/user/pipeline/build_runner.sh
#!/bin/bash
TARGET=$1
echo "Building target: $TARGET"
eval "make -C /home/user/project $TARGET"
EOF
    chmod +x /home/user/pipeline/build_runner.sh

    cat << 'EOF' > /home/user/project/Makefile
all:
	@echo "Building all"
clean:
	@echo "Cleaning"
EOF

    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <string.h>
int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "AUTH_KEY_9921_DEV") == 0) {
        printf("Access Granted\n");
        return 0;
    }
    printf("Access Denied\n");
    return 1;
}
EOF
    gcc -o /home/user/pipeline/tools/validator /tmp/validator.c
    rm /tmp/validator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
