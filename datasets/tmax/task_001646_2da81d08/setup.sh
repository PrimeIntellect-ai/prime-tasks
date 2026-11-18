#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        valgrind \
        build-essential \
        cargo \
        rustc \
        imagemagick \
        ffmpeg \
        fonts-liberation

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/legacy_lib
    mkdir -p /home/user/patches

    # Generate video artifact
    cd /tmp
    convert -size 640x480 xc:white -gravity center -pointsize 24 -fill black -annotate +0+0 "analytics_engine depends on math_routines" 1.png
    convert -size 640x480 xc:white -gravity center -pointsize 24 -fill black -annotate +0+0 "math_routines depends on core_utils" 2.png
    convert -size 640x480 xc:white -gravity center -pointsize 24 -fill black -annotate +0+0 "analytics_engine depends on core_utils" 3.png
    convert -size 640x480 xc:white -gravity center -pointsize 24 -fill black -annotate +0+0 "core_utils depends on base_init" 4.png
    ffmpeg -framerate 1 -i %d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/ci_diagnostic.mp4

    # Create legacy lib
    cat << 'EOF' > /home/user/legacy_lib/main.cpp
#include <iostream>

int main() {
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_lib/Makefile
all: analytics_engine

analytics_engine: main.cpp
	g++ -O0 -g main.cpp -o analytics_engine

test: analytics_engine
	./analytics_engine
EOF

    # Create patches
    cat << 'EOF' > /home/user/patches/base_init.patch
--- main.cpp
+++ main.cpp
@@ -1,4 +1,5 @@
 #include <iostream>

 int main() {
+    // base_init
     return 0;
 }
EOF

    cat << 'EOF' > /home/user/patches/core_utils.patch
--- main.cpp
+++ main.cpp
@@ -2,4 +2,5 @@

 int main() {
     // base_init
+    // core_utils
     return 0;
 }
EOF

    cat << 'EOF' > /home/user/patches/math_routines.patch
--- main.cpp
+++ main.cpp
@@ -3,4 +3,5 @@
 int main() {
     // base_init
     // core_utils
+    // math_routines
     return 0;
 }
EOF

    cat << 'EOF' > /home/user/patches/analytics_engine.patch
--- main.cpp
+++ main.cpp
@@ -4,4 +4,11 @@
     // base_init
     // core_utils
     // math_routines
+    int* arr = new int[10];
+    for(int i=0; i<=10; ++i) { // off-by-one
+        arr[i] = i;
+    }
+    // memory leak: no delete[] arr;
+    std::cout << "Analytics Engine V2: 0 memory leaks. Execution successful." << std::endl;
     return 0;
 }
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
