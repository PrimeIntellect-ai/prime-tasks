#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc make libssl-dev
    pip3 install pytest

    mkdir -p /app/extractor_src
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create ransom note image
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'PAYLOAD_KEY: 8A4F9E2C0B1D7653'" /app/ransom_note.png

    # Create extractor source
    cat << 'EOF' > /app/extractor_src/extractor.h
#ifndef EXTRACTOR_H
#define EXTRACTOR_H
void extract_obfuscated_strings(const char* filename);
#endif
EOF

    cat << 'EOF' > /app/extractor_src/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include "extractor.h"

void extract_obfuscated_strings(const char* filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return;
    int c;
    while ((c = fgetc(f)) != EOF) {
        if (isprint(c)) putchar(c);
        else putchar('\n');
    }
    fclose(f);
}
EOF

    cat << 'EOF' > /app/extractor_src/main.c
#include <stdio.h>
#include "extractor.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    // Deliberate error: calling extract_strings instead of extract_obfuscated_strings
    extract_strings(argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /app/extractor_src/Makefile
CC = gcc
CFLAGS = -Wall

bin_extractor: main.o extractor.o
	$(CC) $(CFLAGS) -o bin_extractor main.o extractor.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

extractor.o: extractor.c
	$(CC) $(CFLAGS) -c extractor.c

clean:
	rm -f *.o bin_extractor
EOF

    # Create corpora
    cat << 'EOF' > /tmp/clean.c
#include <stdio.h>
int main() { printf("Hello clean world\n"); return 0; }
EOF
    gcc /tmp/clean.c -o /app/corpora/clean/clean_bin_1
    gcc /tmp/clean.c -o /app/corpora/clean/clean_bin_2

    cat << 'EOF' > /tmp/evil.c
#include <stdio.h>
const char* hidden_key = "8A4F9E2C0B1D7653";
int main() { printf("Doing evil things...\n"); return 0; }
EOF
    gcc /tmp/evil.c -o /app/corpora/evil/evil_bin_1
    gcc /tmp/evil.c -o /app/corpora/evil/evil_bin_2

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
