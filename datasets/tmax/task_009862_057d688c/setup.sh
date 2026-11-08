#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /home/user/log_parser

cat << 'EOF' > /home/user/log_parser/parser.c
#include <stdio.h>
#include <string.h>

void process_log(const char *log_line) {
    char username[32];
    const char *user_ptr = strstr(log_line, "User:");
    if (user_ptr) {
        user_ptr += 5;
        const char *space_ptr = strchr(user_ptr, ' ');
        if (space_ptr) {
            int len = space_ptr - user_ptr;
            // VULNERABILITY: Stack buffer overflow
            for(int i = 0; i < len; i++) {
                username[i] = user_ptr[i];
            }
            username[len] = '\0';
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char line[1024];
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    while (fgets(line, sizeof(line), f)) {
        process_log(line);
    }
    fclose(f);
    return 0;
}
EOF

cat << 'EOF' > /home/user/log_parser/Makefile
all:
	gcc -O0 -fno-stack-protector -o parser parser.c
EOF

python3 -c '
import random
random.seed(42)
with open("/home/user/log_parser/logs.txt", "w") as f:
    for i in range(1, 10001):
        if i == 4200:
            # Anomalous line causing overflow
            f.write("INFO User:" + ("A"*150) + " Action:LOGIN\n")
        else:
            un_len = random.randint(5, 15)
            un = "".join(random.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(un_len))
            f.write(f"INFO User:{un} Action:LOGIN\n")
'

cd /home/user/log_parser && make

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
