#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/bin
    mkdir -p /home/user/project/lib
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create dummy libmocklog.a
    touch dummy.c
    gcc -c dummy.c
    ar rcs /home/user/project/lib/libmocklog.a dummy.o
    rm dummy.c dummy.o

    # Create broken Makefile
    cat << 'EOF' > /home/user/project/Makefile
CC = gcc
CFLAGS = -I/wrong/path
LDFLAGS = -L/wrong/path -lmocklog

all: bin/log_sanitizer

bin/log_sanitizer: src/main.c src/sanitizer.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
EOF

    # Generate clean files
    for i in $(seq 1 20); do
        echo "This is a clean log file with no bad stuff. Line $i" > /app/corpus/clean/file_$i.txt
    done

    # Generate evil files
    for i in $(seq 1 7); do
        echo "This has <script> tags" > /app/corpus/evil/evil_$i.txt
    done
    for i in $(seq 8 14); do
        echo "This has DROP_TABLE in it" > /app/corpus/evil/evil_$i.txt
    done
    for i in $(seq 15 20); do
        echo -e "This has a bell \x07 character" > /app/corpus/evil/evil_$i.txt
    done

    # Generate audio
    espeak-ng -w /app/qa_report.wav "The build is failing because the include paths are wrong. For the sanitizer, you must reject any file containing the exact string 'DROP_TABLE', any file containing HTML angle brackets, and any file containing non-printable ASCII characters below decimal 32, except for standard carriage returns and newlines."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
