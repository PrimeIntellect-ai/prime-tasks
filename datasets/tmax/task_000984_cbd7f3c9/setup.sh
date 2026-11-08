#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        socat \
        bc \
        gcc \
        fonts-dejavu-core

    pip3 install pytest Pillow

    # Create /app/config.png
    mkdir -p /app
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 200), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
except:
    font = None
d.text((10,10), "DEPLOYMENT CONFIGURATION\nPORT: 8443\nAUTH_TOKEN: X79-PRECISION-BUILD", fill='black', font=font)
img.save('/app/config.png')
EOF
    python3 /tmp/make_img.py

    # Create build system files
    mkdir -p /home/user/build_system

    cat << 'EOF' > /home/user/build_system/main.c
#include <stdio.h>
int part_a();
int part_b();
int main() { printf("OK\n"); return 0; }
EOF

    cat << 'EOF' > /home/user/build_system/build.sh
#!/bin/bash
# Race condition: both functions use 'temp.c'
function build_part_a {
    echo "int part_a() { return 1; }" > temp.c
    gcc -c temp.c -o a.o
}
function build_part_b {
    echo "int part_b() { return 2; }" > temp.c
    gcc -c temp.c -o b.o
}
build_part_a &
build_part_b &
wait
gcc a.o b.o main.c -o server_bin
chmod +x server.sh
EOF

    cat << 'EOF' > /home/user/build_system/calc_factor.sh
#!/bin/bash
# Precision loss here
echo "104348 / 33215" | bc
EOF

    cat << 'EOF' > /home/user/build_system/server.sh
#!/bin/bash
PORT=$1
TOKEN=$2
FACTOR=$3
socat TCP4-LISTEN:${PORT},reuseaddr,fork EXEC:"./handle_req.sh ${TOKEN} ${FACTOR}"
EOF

    cat << 'EOF' > /home/user/build_system/handle_req.sh
#!/bin/bash
read request
read auth_header

if [[ "$auth_header" == *"Bearer $1"* ]]; then
    echo -e "HTTP/1.1 200 OK\r\nContent-Length: ${#2}\r\n\r\n$2"
else
    echo -e "HTTP/1.1 401 Unauthorized\r\n\r\n"
fi
EOF

    chmod +x /home/user/build_system/*.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
