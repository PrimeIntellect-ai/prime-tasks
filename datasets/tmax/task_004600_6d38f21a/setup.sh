#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev file coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/artifacts

    cat << 'EOF' > /tmp/main.c
#include <stdio.h>
int main() { printf("Hello World!\n"); return 0; }
EOF

    cat << 'EOF' > /tmp/lib.c
int add(int a, int b) { return a + b; }
EOF

    cat << 'EOF' > /tmp/app.c
#include <stdio.h>
int data[5000]; // Make it slightly larger
int main() { 
    for(int i=0; i<5000; i++) data[i] = i;
    printf("Data %d\n", data[4999]); 
    return 0; 
}
EOF

    cat << 'EOF' > /tmp/util.c
void noop() { return; }
EOF

    # Compile to targets
    gcc -o /home/user/project/artifacts/blobA /tmp/main.c
    gcc -c -o /home/user/project/artifacts/blobB /tmp/lib.c
    echo "Just some random text data" > /home/user/project/artifacts/blobC
    gcc -o /home/user/project/artifacts/blobD /tmp/app.c
    gcc -c -o /home/user/project/artifacts/blobE /tmp/util.c
    echo "Another text file" > /home/user/project/artifacts/blobF

    rm /tmp/main.c /tmp/lib.c /tmp/app.c /tmp/util.c

    chmod -R 777 /home/user
