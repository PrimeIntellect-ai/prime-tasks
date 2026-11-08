#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils imagemagick ffmpeg fonts-dejavu-core ghostscript
pip3 install pytest

mkdir -p /app

# Create oracle binary
cat << 'EOF' > /app/token_checker.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define SERVER_SEED 0x5A

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("ERROR: Invalid arguments\n");
        return 1;
    }

    char *cookie = argv[1];
    char *session_start = strstr(cookie, "SessionId=");

    if (!session_start) {
        printf("ERROR: Invalid SessionId\n");
        return 1;
    }

    session_start += 10;
    char hex_str[256] = {0};
    int i = 0;
    while (session_start[i] != ';' && session_start[i] != '\0' && i < 255) {
        hex_str[i] = session_start[i];
        i++;
    }

    if (i % 2 != 0 || i == 0) {
        printf("ERROR: Invalid SessionId\n");
        return 1;
    }

    printf("TOKEN: ");
    for (int j = 0; j < i; j += 2) {
        char byte_str[3] = {hex_str[j], hex_str[j+1], '\0'};
        int val = (int)strtol(byte_str, NULL, 16);
        val = val ^ SERVER_SEED;
        val = ((val << 1) | (val >> 7)) & 0xFF; // Left circular shift by 1
        printf("%02x", val);
    }
    printf("\n");
    return 0;
}
EOF

gcc -O2 /app/token_checker.c -o /app/token_checker
strip /app/token_checker
rm /app/token_checker.c

# Create video
cat << 'EOF' > /tmp/gen_video.sh
#!/bin/bash
mkdir -p /tmp/frames
for i in {1..30}; do
    convert -size 640x480 xc:black -font DejaVu-Sans-Mono -pointsize 24 -fill white \
    -draw "text 20,40 'Initializing secure sandbox...'" \
    -draw "text 20,80 'Loading CSP rules... OK'" \
    -draw "text 20,120 'Generating entropy...'" \
    -draw "text 20,160 'SERVER_SEED: 0x5A'" \
    -draw "text 20,200 'Starting listener on port 8080...'" \
    /tmp/frames/frame_$(printf "%03d" $i).png
done
ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/debug_session.mp4
rm -rf /tmp/frames
EOF
bash /tmp/gen_video.sh
rm /tmp/gen_video.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
