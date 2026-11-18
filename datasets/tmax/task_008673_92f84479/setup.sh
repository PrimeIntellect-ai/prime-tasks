#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc iptables coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensics

    cat << 'EOF' > /home/user/forensics/attacker_tool.c
#include <stdio.h>
#include <string.h>

#define C2_SERVER "203.0.113.88"

void process_command(char *input) {
    char buffer[64];
    // Vulnerability: Classic Buffer Overflow
    strcpy(buffer, input);
    printf("Executing command from %s: %s\n", C2_SERVER, buffer);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        process_command(argv[1]);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/forensics/stolen_data.txt
John Doe, dob: 1980-01-01, ssn: 123-45-6789, balance: $5000
Jane Smith, dob: 1992-05-15, ssn: 987-65-4321, balance: $12000
System Admin, notes: "Call the bank about 000-11-2222 tomorrow."
EOF

    echo "MOCK_MALWARE_PAYLOAD_BYTES_998877665544332211" > /home/user/forensics/malware_payload.bin

    chmod -R 777 /home/user
