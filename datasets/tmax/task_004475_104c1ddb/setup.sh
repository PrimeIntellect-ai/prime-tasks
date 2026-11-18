#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        gcc \
        make \
        patch \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest flask fastapi uvicorn requests pytesseract pillow

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/c_backend

    # Generate config.png
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +20+50 "SERVICE CONFIGURATION\nPORT: 9055\nAUTH_TOKEN: alpha-beta-gamma" /app/config.png

    # Create algo.c
    cat << 'EOF' > /home/user/c_backend/algo.c
#include <stdio.h>

double weighted_trace(double* matrix, double* weights, int size) {
    double sum = 0.0;
    for (int i = 0; i < size; i++) {
        // BUG: Using i instead of i*size + i for the diagonal element
        sum += weights[i] * matrix[i]; 
    }
    return sum;
}
EOF

    # Create fix_algo.patch
    cat << 'EOF' > /home/user/fix_algo.patch
--- algo.c
+++ algo.c
@@ -4,8 +4,7 @@
 double weighted_trace(double* matrix, double* weights, int size) {
     double sum = 0.0;
     for (int i = 0; i < size; i++) {
-        // BUG: Using i instead of i*size + i for the diagonal element
-        sum += weights[i] * matrix[i]; 
+        sum += weights[i] * matrix[i * size + i];
     }
     return sum;
 }
EOF

    # Create Makefile with spaces instead of tabs
    cat << 'EOF' > /home/user/c_backend/Makefile
all:
    gcc -shared -o libalgo.so -fPIC algo.c
EOF
    # Ensure spaces are used
    sed -i 's/\t/    /g' /home/user/c_backend/Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
