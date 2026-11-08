#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak ffmpeg
    pip3 install pytest

    # Install PyTorch CPU to save time and space, then whisper
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/voice_memo.wav "The configuration stream consists of sequential chunks. Each chunk begins with a 32-bit unsigned little-endian integer. This integer represents the number of UTF-16LE characters—not bytes—that follow in the chunk's payload. Read the UTF-16LE payload, convert it to UTF-8, and write the UTF-8 string to standard output, followed by a single newline character. If the character count is zero, just print a newline. If you hit EOF before reading a full chunk header, or if the payload is truncated before the expected number of characters are read, exit immediately with status code 1. Continue processing chunks until standard input is exhausted."

    # Create and compile the oracle parser
    cat << 'EOF' > /app/oracle_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <iconv.h>

int main() {
    uint32_t char_count;
    iconv_t cd = iconv_open("UTF-8", "UTF-16LE");
    if (cd == (iconv_t)-1) return 1;

    while (fread(&char_count, sizeof(uint32_t), 1, stdin) == 1) {
        if (char_count == 0) {
            printf("\n");
            continue;
        }
        size_t bytes_to_read = char_count * 2;
        char *inbuf = malloc(bytes_to_read);
        if (fread(inbuf, 1, bytes_to_read, stdin) != bytes_to_read) {
            free(inbuf);
            exit(1);
        }

        size_t inbytesleft = bytes_to_read;
        size_t outbytesleft = bytes_to_read * 4;
        char *outbuf = malloc(outbytesleft);
        char *inptr = inbuf;
        char *outptr = outbuf;

        if (iconv(cd, &inptr, &inbytesleft, &outptr, &outbytesleft) == (size_t)-1) {
            // Error handling could be added here
        }

        fwrite(outbuf, 1, outptr - outbuf, stdout);
        printf("\n");
        free(inbuf);
        free(outbuf);
    }

    if (!feof(stdin)) {
        exit(1);
    }

    iconv_close(cd);
    return 0;
}
EOF
    gcc -O2 -o /app/oracle_parser /app/oracle_parser.c
    rm /app/oracle_parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
