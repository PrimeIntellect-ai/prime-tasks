#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo espeak ffmpeg curl
    pip3 install pytest

    mkdir -p /app/libnormalize
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /app/verifier_corpus/clean
    mkdir -p /app/verifier_corpus/evil

    # Generate the voicemail audio
    espeak -w /app/voicemail.wav "Emergency update. The attackers are using a new payload keyword. You must block the word: bloodhound. I repeat, block bloodhound."

    # Create the C library
    cat << 'EOF' > /app/libnormalize/normalize.c
#include <string.h>
void normalize_text(char* input) {
    int j = 0;
    for (int i = 0; input[i] != '\0'; i++) {
        if ((unsigned char)input[i] == 0xE2 && (unsigned char)input[i+1] == 0x80 && (unsigned char)input[i+2] == 0x8B) {
            i += 2; // skip zero-width space
            continue;
        }
        if (input[i] >= 'A' && input[i] <= 'Z') {
            input[j++] = input[i] + 32;
        } else {
            input[j++] = input[i];
        }
    }
    input[j] = '\0';
}
EOF

    # Populate corpus
    echo "This is a completely safe text file." > /app/corpus/clean/safe1.txt
    echo "Another safe file without any bad words." > /app/corpus/clean/safe2.txt
    echo "Select * from users where username = 'admin' OR 1=1;" > /app/corpus/evil/evil1.txt
    # The word bloodhound with a zero-width space (U+200B) in the middle
    echo -e "bl\xE2\x80\x8Boodhound is bad" > /app/corpus/evil/evil2.txt

    # Populate verifier corpus
    echo "Clean text for verification." > /app/verifier_corpus/clean/test1.txt
    echo "OR 1=1 is not good." > /app/verifier_corpus/evil/test1.txt
    echo "We must stop the bloodhound." > /app/verifier_corpus/evil/test2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
