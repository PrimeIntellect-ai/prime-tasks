#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary tools for the task (OCR, compilation, image generation, networking, reverse engineering)
    apt-get install -y imagemagick fonts-dejavu-core gcc tesseract-ocr socat nmap curl binutils xxd

    # Create the app directory
    mkdir -p /app

    # Generate the target info image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 32 -fill black -draw "text 20,60 'TARGET_PIN: 4921'" /app/target_info.png

    # Create the dummy validator binary to be reverse engineered
    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char salt[] = "SALT_RED_TEAM_2024";
    char algo[] = "sha256sum";
    printf("Validating token using %s with salt %s...\n", algo, salt);
    return 0;
}
EOF
    gcc -o /app/token_validator /tmp/validator.c
    chmod +x /app/token_validator
    rm /tmp/validator.c

    # Create user and set home permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
