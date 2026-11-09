#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest pillow

    mkdir -p /app

    # Generate dev_note.png
    cat << 'EOF' > /app/gen_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "TLS Pin: A1B2C3D4E5F6G7H8\nSalt: SaltySecret99", fill=(0,0,0))
img.save('/app/dev_note.png')
EOF
    python3 /app/gen_img.py
    rm /app/gen_img.py

    # Generate ref_auth_gen
    cat << 'EOF' > /app/ref.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/sha.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    char *username = argv[1];
    char *password = argv[2];

    if (strstr(username, "../") != NULL || strstr(username, "..\\\\") != NULL) {
        printf("{\"error\": \"invalid username\"}\n");
        return 0;
    }

    char *pin = "A1B2C3D4E5F6G7H8";
    char *salt = "SaltySecret99";

    int len = strlen(pin) + strlen(username) + strlen(password) + strlen(salt);
    char *concat = malloc(len + 1);
    strcpy(concat, pin);
    strcat(concat, username);
    strcat(concat, password);
    strcat(concat, salt);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)concat, len, hash);

    printf("{\"username\": \"%s\", \"token\": \"", username);
    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        printf("%02x", hash[i]);
    }
    printf("\"}\n");

    free(concat);
    return 0;
}
EOF
    gcc -o /app/ref_auth_gen /app/ref.c -lcrypto
    chmod +x /app/ref_auth_gen
    rm /app/ref.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
