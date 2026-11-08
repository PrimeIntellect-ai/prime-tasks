#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo gcc openssl espeak-ng
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create app directory
    mkdir -p /app

    # 1. Create voicemail
    espeak-ng -w /app/admin_voicemail.wav "The password for the legacy keystore is Alpha Tango Niner two zero two three"

    # 2. Create legacy keystore
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /tmp/cert.pem -days 365 -nodes -subj "/CN=Legacy"
    openssl pkcs12 -export -out /app/legacy_keystore.p12 -inkey /tmp/key.pem -in /tmp/cert.pem -password pass:AlphaTangoNiner2023
    rm /tmp/key.pem /tmp/cert.pem

    # 3. Create privesc vector (sudoers)
    echo "user ALL=(ALL) NOPASSWD: /bin/cat" > /etc/sudoers.d/user_cat
    chmod 0440 /etc/sudoers.d/user_cat

    # 4. Create legacy validator
    mkdir -p /opt/legacy
    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[4];
    if (fread(magic, 1, 4, f) != 4) {
        printf("INVALID\n");
        fclose(f);
        return 1;
    }
    if (magic[0] != 'C' || magic[1] != 'E' || magic[2] != 'R' || magic[3] != 'T') {
        printf("INVALID\n");
        fclose(f);
        return 1;
    }

    uint16_t len;
    if (fread(&len, 2, 1, f) != 1) {
        printf("INVALID\n");
        fclose(f);
        return 1;
    }

    uint32_t checksum = 0;
    for (int i = 0; i < len; i++) {
        int c = fgetc(f);
        if (c == EOF) {
            printf("INVALID\n");
            fclose(f);
            return 1;
        }
        checksum += c;
    }

    uint32_t expected_checksum;
    if (fread(&expected_checksum, 4, 1, f) != 1) {
        printf("INVALID\n");
        fclose(f);
        return 1;
    }

    if (checksum == expected_checksum) {
        printf("VALID\n");
        fclose(f);
        return 0;
    } else {
        printf("INVALID\n");
        fclose(f);
        return 1;
    }
}
EOF
    gcc -O2 /tmp/validator.c -o /opt/legacy/validator
    strip /opt/legacy/validator
    rm /tmp/validator.c

    chown root:root /opt/legacy/validator
    chmod 0700 /opt/legacy/validator

    # Final permissions
    chmod -R 777 /home/user
