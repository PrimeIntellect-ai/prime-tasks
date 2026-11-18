#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/incident
    cd /home/user/incident

    # 1. Create the plaintext
    cat << 'EOF' > exfil_original.txt
CUSTOMER_DATA_START
ID: 101, Name: Alice, Card: 4111-2222-3333-4444, Balance: $500
ID: 102, Name: Bob, Card: 5555-6666-7777-8888, Balance: $1200
ID: 103, Name: Charlie, Card: 3782-1111-2222-9999, Balance: $30
CUSTOMER_DATA_END
EOF

    # 2. Create the malware.c
    cat << 'EOF' > malware.c
#include <stdio.h>
#include <stdlib.h>

// Weak encryption tool
void encrypt_file(const char* infile, const char* outfile, unsigned short seed) {
    FILE *fin = fopen(infile, "rb");
    FILE *fout = fopen(outfile, "wb");
    if (!fin || !fout) exit(1);

    unsigned int state = seed;
    int c;
    while ((c = fgetc(fin)) != EOF) {
        state = (state * 1103515245 + 12345) & 0x7fffffff;
        fputc(c ^ (state & 0xFF), fout);
    }
    fclose(fin);
    fclose(fout);
}

int main(int argc, char** argv) {
    if (argc != 4) {
        printf("Usage: %s <infile> <outfile> <seed>\n", argv[0]);
        return 1;
    }
    unsigned short seed = (unsigned short)atoi(argv[3]);
    encrypt_file(argv[1], argv[2], seed);
    return 0;
}
EOF

    # 3. Compile and encrypt with a specific seed
    gcc malware.c -o malware
    ./malware exfil_original.txt exfil.enc 1337

    # 4. Generate checksum
    sha256sum exfil_original.txt > checksum.sha256

    # 5. Cleanup
    rm exfil_original.txt malware

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
