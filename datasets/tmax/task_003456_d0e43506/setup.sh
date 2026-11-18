#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate source video
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=24 -c:v libx264 /app/source.mp4

    # Create broken hasher.c
    cat << 'EOF' > /home/user/hasher.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    unsigned char buf[1024];
    unsigned long long checksum = 0;
    int c, i = 0;
    // BUG: doesn't check bounds
    while ((c = getchar()) != EOF) {
        buf[i++] = c;
    }
    for (int j = 0; j < i; j++) {
        checksum += buf[j];
    }
    printf("%llx\n", checksum);
    return 0;
}
EOF

    # Create oracle_hasher.c
    cat << 'EOF' > /app/oracle_hasher.c
#include <stdio.h>
int main() {
    unsigned long long checksum = 0;
    int c;
    while ((c = getchar()) != EOF) {
        checksum += c;
    }
    printf("%llx\n", checksum);
    return 0;
}
EOF

    # Compile oracle_hasher
    gcc -O2 /app/oracle_hasher.c -o /app/oracle_hasher

    # Create oracle.sh
    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
URL=$1
# Extract the number parameter
N=$(echo "$URL" | grep -oP '(?<=number=)[0-9]+')
ffmpeg -y -loglevel error -i /app/source.mp4 -vf "select=eq(n\,$N)" -vframes 1 -f image2pipe -vcodec rawvideo -pix_fmt rgb24 - | /app/oracle_hasher
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
