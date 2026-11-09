#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg netcat-openbsd socat
pip3 install pytest

mkdir -p /home/user/src/lib
mkdir -p /home/user/frames
mkdir -p /app

# Create libcore.c
cat << 'EOF' > /home/user/src/lib/libcore.c
#include <stdio.h>
void process_image(const char* filepath) {
    // Mock behavior: if filepath ends with frame_14.png, print SCORE_84
    int is_14 = 0;
    for(int i=0; filepath[i] != '\0'; i++) {
        if (filepath[i] == '1' && filepath[i+1] == '4' && filepath[i+2] == '.') {
            is_14 = 1;
        }
    }
    if (is_14) {
        printf("RESULT_SCORE_84\n");
    } else {
        printf("RESULT_SCORE_10\n");
    }
}
EOF

# Compile libcore.so
gcc -shared -fPIC -o /home/user/src/lib/libcore.so /home/user/src/lib/libcore.c

# Create analyzer.c
cat << 'EOF' > /home/user/src/analyzer.c
#include <stdio.h>
extern void process_image(const char* filepath);
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    process_image(argv[1]);
    return 0;
}
EOF

# Create broken build.sh
cat << 'EOF' > /home/user/src/build.sh
#!/bin/bash
gcc analyzer.c -o analyzer
EOF
chmod +x /home/user/src/build.sh

# Generate test_stream.mp4 (30 seconds, 1 fps)
ffmpeg -f lavfi -i testsrc=duration=30:size=320x240:rate=1 -c:v libx264 /app/test_stream.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
