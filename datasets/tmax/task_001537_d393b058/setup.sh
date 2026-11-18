#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        git \
        cargo \
        gcc \
        espeak \
        cron \
        logrotate \
        ffmpeg

    pip3 install pytest

    mkdir -p /app

    # Generate the voicemail audio
    espeak -w /app/voicemail.wav "Hey, it's Dave. I'm heading out on PTO. Just remember for the migration, the secret project codename is VANGUARD. Make sure the hook checks for it. See ya."

    # Create the legacy C binary
    cat << 'EOF' > /app/legacy_ticket_extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>

int main() {
    char buffer[8192];
    size_t bytes_read = fread(buffer, 1, sizeof(buffer) - 1, stdin);
    buffer[bytes_read] = '\0';

    regex_t regex;
    if (regcomp(&regex, "[A-Z]{3,5}-[0-9]{3,6}", REG_EXTENDED)) return 1;

    regmatch_t pmatch[1];
    char *s = buffer;
    int found = 0;
    while (regexec(&regex, s, 1, pmatch, 0) == 0) {
        if (found) printf(",");
        int len = pmatch[0].rm_eo - pmatch[0].rm_so;
        printf("%.*s", len, s + pmatch[0].rm_so);
        s += pmatch[0].rm_eo;
        found = 1;
    }

    if (!found) {
        printf("NO_TICKET");
    }

    regfree(&regex);
    return 0;
}
EOF

    gcc -O3 /app/legacy_ticket_extractor.c -o /app/legacy_ticket_extractor
    rm /app/legacy_ticket_extractor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
