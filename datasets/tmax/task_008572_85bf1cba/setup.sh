#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > main.c
#include <stdio.h>

void utils_func();

int main() {
    utils_func();
    printf("Build success!\n");
    return 0;
}
EOF

    cat << 'EOF' > utils.c
#include <stdio.h>

void utils_func() {
    printf("Utils module loaded.\n");
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash

echo "Compiling main.c..."
gcc -c main.c

echo "Compiling utils.c..."
gcc -c utils.c

echo "Linking..."
# BUG: Forgetting to link the other object file
gcc main.o -o app

echo "Done!"
EOF

    chmod +x build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
