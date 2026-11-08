#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app

    # Create the legacy parser C source
    cat << 'EOF' > /app/legacy_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void trim(char *str) {
    char *start = str;
    while(isspace((unsigned char)*start)) start++;
    char *end = start + strlen(start) - 1;
    while(end > start && isspace((unsigned char)*end)) end--;
    *(end+1) = '\0';
    memmove(str, start, strlen(start) + 1);
}

int is_pos_int(const char *str) {
    if (!*str) return 0;
    for (int i = 0; str[i]; i++) {
        if (!isdigit((unsigned char)str[i])) return 0;
    }
    if (atoi(str) <= 0) return 0;
    return 1;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("[Stage:canary|Lang:en_US.UTF-8|TZ:UTC|Cores:2]\n");
        return 0;
    }

    char *input = strdup(argv[1]);
    char *fields[4] = {"", "", "", ""};

    char *token = input;
    for (int i = 0; i < 4; i++) {
        if (!token) break;
        char *comma = strchr(token, ',');
        if (comma) {
            *comma = '\0';
            fields[i] = token;
            token = comma + 1;
        } else {
            fields[i] = token;
            token = NULL;
        }
    }

    for (int i = 0; i < 4; i++) {
        trim(fields[i]);
    }

    const char *stage = strlen(fields[0]) > 0 ? fields[0] : "canary";
    const char *locale = strlen(fields[1]) > 0 ? fields[1] : "en_US.UTF-8";
    const char *tz = strlen(fields[2]) > 0 ? fields[2] : "UTC";
    const char *cores = (strlen(fields[3]) > 0 && is_pos_int(fields[3])) ? fields[3] : "2";

    printf("[Stage:%s|Lang:%s|TZ:%s|Cores:%s]\n", stage, locale, tz, cores);

    free(input);
    return 0;
}
EOF

    # Compile the legacy parser
    gcc -O2 /app/legacy_parser.c -o /app/legacy_parser
    chmod +x /app/legacy_parser
    rm /app/legacy_parser.c

    # Generate the screenshot
    convert -background white -fill black -font Liberation-Sans -pointsize 24 label:"Deployment Config Parser Rules:\nInput format: STAGE,LOCALE,TIMEZONE,CORES\n1. Trim leading/trailing spaces from each field.\n2. If STAGE is empty, default to 'canary'.\n3. If LOCALE is empty, default to 'en_US.UTF-8'.\n4. If TIMEZONE is empty, default to 'UTC'.\n5. If CORES is empty or not a positive integer, default to '2'.\nOutput format: [Stage:STAGE|Lang:LOCALE|TZ:TIMEZONE|Cores:CORES]" /app/vnc_screenshot.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
