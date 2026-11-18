#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y ffmpeg tesseract-ocr bubblewrap openssl gcc fonts-liberation wget

    mkdir -p /app

    # Create dummy HTTP payload
    cat << 'EOF' > /tmp/payload.txt
GET /api/data HTTP/1.1
Host: example.com
Cookie: Session-Token=token1_abc

POST /api/upload HTTP/1.1
Host: example.com
Cookie: Session-Token=token2_def
EOF

    # Encrypt and base64 encode
    KEY="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    IV="0123456789abcdef0123456789abcdef"
    openssl enc -aes-256-cbc -K $KEY -iv $IV -in /tmp/payload.txt -out /tmp/payload.enc
    base64 -w 0 /tmp/payload.enc > /tmp/payload.b64

    # Generate video with base64 text
    B64_TEXT=$(cat /tmp/payload.b64)
    ffmpeg -f lavfi -i color=c=black:s=800x600:d=2 -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf:fontsize=18:fontcolor=white:x=10:y=10:text='$B64_TEXT'" -c:v libx264 /app/exfil_video.mp4

    # Create suspicious service source code
    cat << 'EOF' > /tmp/malware.c
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main() {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in servaddr;
    servaddr.sin_family = AF_INET;
    servaddr.sin_port = htons(80);
    inet_pton(AF_INET, "8.8.8.8", &servaddr.sin_addr);

    // Attempt to connect to a dummy external IP. 
    // If bwrap --unshare-net is used, this will fail.
    if (connect(sockfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) != 0) {
        printf("KEY: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n");
        printf("IV: 0123456789abcdef0123456789abcdef\n");
        exit(0);
    }
    printf("Connected to C2.\n");
    close(sockfd);
    return 0;
}
EOF

    # Compile suspicious service
    gcc /tmp/malware.c -o /app/suspicious_service
    chmod +x /app/suspicious_service

    # Cleanup temp files
    rm -f /tmp/payload.txt /tmp/payload.enc /tmp/payload.b64 /tmp/malware.c

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
