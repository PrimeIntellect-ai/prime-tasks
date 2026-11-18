#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make valgrind
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user/organizer

    # Create oracle
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if(argc != 4) return 1;
    long long size = atoll(argv[1]);
    long long mask = atoll(argv[2]);
    long long id = atoll(argv[3]);
    long long bucket = ((size ^ mask) + id) % 1000;
    printf("%lld\n", bucket);
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle
    strip /app/oracle
    rm /app/oracle.c

    # Create formula.png using Pillow
    cat << 'EOF' > /app/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((50, 100), "BUCKET = ((SIZE ^ MASK) + ID) % 1000", fill=(0, 0, 0))
img.save('/app/formula.png')
EOF
    python3 /app/make_image.py
    rm /app/make_image.py

    # Create helper.cpp
    cat << 'EOF' > /home/user/organizer/helper.cpp
extern "C" {
    int safe_mod(int a, int b) {
        if (b == 0) return 0;
        return a % b;
    }
}
EOF

    # Create classifier.c
    cat << 'EOF' > /home/user/organizer/classifier.c
#include <stdio.h>
#include <stdlib.h>

extern int safe_mod(int a, int b);

int main(int argc, char **argv) {
    if (argc != 4) return 1;

    // Intentional leak for agent to fix
    int* leaky = (int*)malloc(sizeof(int) * 10);
    leaky[0] = atoi(argv[1]);

    long long size = atoll(argv[1]);
    long long mask = atoll(argv[2]);
    long long id = atoll(argv[3]);

    // Agent must implement formula here using safe_mod
    long long result = 0; 

    printf("%lld\n", result);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
