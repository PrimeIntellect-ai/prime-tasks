#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr strace g++ fonts-dejavu-core
pip3 install pytest

mkdir -p /home/user/parser
mkdir -p /app

# 1. Create the fixture image
convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,40 'NEW FORMAT SPECS'" -draw "text 10,80 'DELIM: #DATA#'" -draw "text 10,120 'OFFSET: 4'" /app/whiteboard.png

# 2. Generate the memory dump
python3 -c '
import random
with open("/app/mem_dump.bin", "wb") as f:
    # write 5MB of garbage
    f.write(b"x" * 5000000)

    # write 50 valid chunks
    for i in range(50):
        f.write(b"#DATA#")
        f.write(b"A" * 4) # offset
        s = f"ValidString_{i}".encode()
        f.write(bytes([len(s)]))
        f.write(s)
        f.write(b"y" * 1000)

    # write a crash-inducing chunk (length = 255)
    f.write(b"#DATA#")
    f.write(b"B" * 4)
    f.write(bytes([255]))
    f.write(b"CRASH") # not enough bytes for 255
    f.write(b"z" * 1000)
'

# 3. Create the slow, buggy C++ code
cat << 'EOF' > /home/user/parser/parser.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <unistd.h>
#include <fcntl.h>
#include <cstring>

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;

    const char* delim = "OLD_DELIM";
    int offset = 0;
    int delim_len = strlen(delim);

    int fd = open(argv[1], O_RDONLY);
    std::ofstream out(argv[2]);

    char c;
    int match_idx = 0;

    // Inefficient byte-by-byte read using syscalls
    while (read(fd, &c, 1) == 1) {
        if (c == delim[match_idx]) {
            match_idx++;
            if (match_idx == delim_len) {
                // Delimiter found, skip offset
                for(int i=0; i<offset; i++) {
                    read(fd, &c, 1);
                }
                // Read length
                unsigned char len;
                read(fd, &len, 1);

                // BUG: No bounds checking, allocates and reads blindly
                char* buf = new char[len + 1];
                for(int i=0; i<len; i++) {
                    read(fd, &buf[i], 1);
                }
                buf[len] = '\0';
                out << buf << "\n";
                delete[] buf;

                match_idx = 0;
            }
        } else {
            match_idx = (c == delim[0]) ? 1 : 0;
        }
    }
    close(fd);
    return 0;
}
EOF

# 4. Generate truth expected output
python3 -c '
with open("/app/expected_strings.txt", "w") as f:
    for i in range(50):
        f.write(f"ValidString_{i}\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
