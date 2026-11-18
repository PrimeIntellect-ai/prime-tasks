#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake git wget espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /app/uploads

    # Generate audio for voicemail
    espeak-ng -w /tmp/temp.wav "The attacker exploited the upload handler to overwrite slash root slash dot ssh slash authorized keys."
    ffmpeg -i /tmp/temp.wav -ar 16000 -ac 1 -c:a pcm_s16le /app/voicemail.wav
    rm /tmp/temp.wav

    # Install whisper.cpp
    git clone https://github.com/ggerganov/whisper.cpp.git /opt/whisper.cpp
    cd /opt/whisper.cpp
    git checkout v1.5.4
    make
    bash ./models/download-ggml-model.sh base.en

    # Create server.c
    cat << 'EOF' > /app/server.c
#include <stdio.h>
#include <string.h>

int handle_upload(const char* filename, const char* content) {
    // VULNERABLE: No path validation
    char filepath[256];
    snprintf(filepath, sizeof(filepath), "/app/uploads/%s", filename);
    FILE *f = fopen(filepath, "w");
    if (!f) return -1;
    fprintf(f, "%s", content);
    fclose(f);
    return 0;
}

int main() {
    return 0;
}
EOF

    # Create secret logs
    cat << 'EOF' > /app/secret_eval.log
192.168.1.1 - GET /login?username=admin&password=supersecret&submit=1
10.0.0.2 - POST /checkout CC: 1234-5678-9012-3456
192.168.1.5 - POST /checkout CC: 9876543212345678 success
172.16.0.4 - GET /profile?password=foo bar
EOF

    cat << 'EOF' > /app/secret_eval_golden.log
192.168.1.1 - GET /login?username=admin&password=[REDACTED]&submit=1
10.0.0.2 - POST /checkout CC: [REDACTED_CC]
192.168.1.5 - POST /checkout CC: [REDACTED_CC] success
172.16.0.4 - GET /profile?password=[REDACTED] bar
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
