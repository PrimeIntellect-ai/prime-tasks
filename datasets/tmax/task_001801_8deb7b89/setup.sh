#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect gcc ffmpeg libssl-dev
    pip3 install pytest

    mkdir -p /app

    # Create dummy audio file
    touch /app/voicemail.wav

    # Create the interactive transcriber C source
    cat << 'EOF' > /app/transcriber.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char audio_path[256];
    char output_path[256];

    printf("Enter path to audio file: ");
    fflush(stdout);
    if (scanf("%255s", audio_path) != 1) return 1;

    printf("Enter output text file path: ");
    fflush(stdout);
    if (scanf("%255s", output_path) != 1) return 1;

    FILE *f = fopen(output_path, "w");
    if (f) {
        fprintf(f, "Alert system failure detected on node seven. Please restart the primary database daemon immediately.\n");
        fclose(f);
    } else {
        printf("Failed to open output file.\n");
        return 1;
    }
    return 0;
}
EOF

    # Compile the interactive transcriber
    gcc /app/transcriber.c -o /app/interactive_transcriber
    rm /app/transcriber.c
    chmod +x /app/interactive_transcriber

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
