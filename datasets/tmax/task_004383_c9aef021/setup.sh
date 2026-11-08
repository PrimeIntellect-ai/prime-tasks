#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make git tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /home/user/data_processor
    mkdir -p /app

    # Create the schematic image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'FORMULA: A*13 + B*7 - C*3 + OFFSET', fill=(0, 0, 0))
img.save('/app/schematic.png')
"

    # Create the oracle binary
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    int c = atoi(argv[3]);
    if (a < 0 || b < 0 || c < 0) return 2;
    int res = a*13 + b*7 - c*3 + 42;
    printf("%d\n", res);
    return 0;
}
EOF
    gcc -o /app/oracle_bin /app/oracle.c
    rm /app/oracle.c

    # Setup git repository
    cd /home/user/data_processor
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > Makefile
processor: main.c
	gcc -o processor main.c
EOF
    git add Makefile

    # Commit 1
    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    int c = atoi(argv[3]);
    if (a < 0 || b < 0 || c < 0) return 2;
    int res = a*13 + b*7 - c*3 + 42;
    printf("%d\n", res);
    return 0;
}
EOF
    git add main.c
    git commit -m "Initial commit"

    # Commit 2
    sed -i 's/+ 42;/+ 0;/g' main.c
    git commit -am "Update offset"

    # Commit 3
    sed -i 's/if (a < 0 || b < 0 || c < 0)/if (a > 100 || b > 100 || c > 100)/g' main.c
    git commit -am "Update bounds check"

    # Commit 4
    sed -i 's/int res = a\*13 + b\*7 - c\*3 + 0;/int res = a + b + c;/g' main.c
    git commit -am "Simplify formula"

    # Commit 5
    sed -i 's/int res = a + b + c;/int res = a + b + c/g' main.c
    git commit -am "Oops"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
