#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make imagemagick tesseract-ocr libtesseract-dev libleptonica-dev fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/libparser /app/corpus/clean /app/corpus/evil

    # Create the C shared library source
    cat << 'EOF' > /app/libparser/parser.c
#include "parser.h"
int parse_data(const char* buffer, int len) {
    if (len < 4) return -1;
    // Simple mock serialization check: 
    // Data must end with "DONE"
    if (buffer[len-4] == 'D' && buffer[len-3] == 'O' && buffer[len-2] == 'N' && buffer[len-1] == 'E') {
        return 0;
    }
    return -1;
}
EOF

    cat << 'EOF' > /app/libparser/parser.h
#ifndef PARSER_H
#define PARSER_H
int parse_data(const char* buffer, int len);
#endif
EOF

    # Create the broken Makefile (Missing -fPIC for the object file)
    cat << 'EOF' > /app/libparser/Makefile
all: libparser.so

libparser.so: parser.o
	gcc -shared -o libparser.so parser.o

parser.o: parser.c
	gcc -c parser.c
EOF

    # Create the image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'NEW ABI MAGIC HEADER: PY3_V2'" /app/protocol_spec.png

    # Create the clean corpus (Must start with PY3_V2 and end with DONE)
    printf "PY3_V2\x01\x02\x03DONE" > /app/corpus/clean/payload1.bin
    printf "PY3_V2somedataDONE" > /app/corpus/clean/payload2.bin
    printf "PY3_V2DONE" > /app/corpus/clean/payload3.bin

    # Create the evil corpus
    # Wrong magic (Python 2)
    printf "PY2_V1somedataDONE" > /app/corpus/evil/bad1.bin
    # Right magic, invalid payload (missing DONE)
    printf "PY3_V2somedata" > /app/corpus/evil/bad2.bin
    # Completely garbage
    printf "GARBAGE DATA" > /app/corpus/evil/bad3.bin
    # Too short
    printf "PY3_V2" > /app/corpus/evil/bad4.bin

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
