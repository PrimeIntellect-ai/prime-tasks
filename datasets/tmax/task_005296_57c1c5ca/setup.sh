#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace ffmpeg
    pip3 install pytest

    mkdir -p /app /home/user/src

    cat << 'EOF' > /tmp/legacy_parser.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>
int main(int argc, char **argv) {
    if(argc != 2) return 1;
    char *str = argv[1];
    int len = strlen(str);
    for(int i = 0; i < len / 2; i++) {
        char temp = str[i];
        str[i] = str[len - 1 - i];
        str[len - 1 - i] = temp;
    }
    for(int i = 0; i < len; i++) {
        str[i] = toupper(str[i]);
    }
    printf("%s - VERIFIED\n", str);
    return 0;
}
EOF
    gcc -O3 /tmp/legacy_parser.c -o /app/legacy_parser
    chmod +x /app/legacy_parser

    cat << 'EOF' > /home/user/src/main.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>
int main(int argc, char **argv) {
    if(argc != 2) return 1;
    // TODO: implement legacy logic
    printf("%s\n", argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/build.sh
#!/bin/bash
compiler_check_xyz > /dev/null 2>&1
if [ $? -ne 0 ]; then
    exit 1
fi
gcc -O3 main.c -o /home/user/event_parser
EOF
    chmod +x /home/user/src/build.sh

    ffmpeg -y -f lavfi -i "color=c=black:s=320x240:d=10:r=10" -vf "drawbox=x=0:y=0:w=320:h=240:color=white@1:t=fill:enable='between(n,46,46)'" -c:v libx264 /app/incident.mp4 >/dev/null 2>&1

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/src
    chmod -R 777 /home/user
