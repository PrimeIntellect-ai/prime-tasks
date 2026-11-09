#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the memo image
    convert -size 800x600 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -annotate +20+40 "CONFIDENTIAL: SYSTEM TRACKER SPECS" \
        -annotate +20+70 "All tracked properties must use the prefix: 'TRK-v9'" \
        -annotate +20+100 "Track ONLY the following configuration keys:" \
        -annotate +20+130 "- host" \
        -annotate +20+160 "- port" \
        -annotate +20+190 "- timeout" \
        -annotate +20+220 "- retries" \
        -annotate +20+250 "SPECIAL RULE: If the 'retries' value evaluates to a negative integer," \
        -annotate +20+280 "it must be clamped to '0'. Keys are case-insensitive." \
        /app/memo.png

    # Create the oracle
    cat << 'EOF' > /app/oracle_tracker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void urldecode(char *dst, const char *src) {
    char a, b;
    while (*src) {
        if ((*src == '%') &&
            ((a = src[1]) && (b = src[2])) &&
            (isxdigit(a) && isxdigit(b))) {
            if (a >= 'a') a -= 'a'-'A';
            else if (a >= 'A') a -= ('A' - 10);
            else a -= '0';
            if (b >= 'a') b -= 'a'-'A';
            else if (b >= 'A') b -= ('A' - 10);
            else b -= '0';
            *dst++ = 16*a+b;
            src+=3;
        } else {
            *dst++ = *src++;
        }
    }
    *dst++ = '\0';
}

void str_tolower(char *str) {
    for(; *str; ++str) *str = tolower((unsigned char)*str);
}

void trim(char **str) {
    while(isspace((unsigned char)**str)) (*str)++;
    char *end = *str + strlen(*str) - 1;
    while(end >= *str && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
}

int main() {
    char line[8192];
    char *host = NULL, *port = NULL, *retries = NULL, *timeout = NULL;

    while (fgets(line, sizeof(line), stdin)) {
        char *colon = strchr(line, ':');
        if (!colon) continue;
        *colon = '\0';
        char *key = line;
        char *val = colon + 1;

        trim(&key);
        trim(&val);
        str_tolower(key);

        char decoded_val[8192];
        urldecode(decoded_val, val);

        if (strcmp(key, "host") == 0) {
            if (host) free(host);
            host = strdup(decoded_val);
        } else if (strcmp(key, "port") == 0) {
            if (port) free(port);
            port = strdup(decoded_val);
        } else if (strcmp(key, "retries") == 0) {
            if (retries) free(retries);
            retries = strdup(decoded_val);
        } else if (strcmp(key, "timeout") == 0) {
            if (timeout) free(timeout);
            timeout = strdup(decoded_val);
        }
    }

    if (host) printf("TRK-v9-host=%s\n", host);
    if (port) printf("TRK-v9-port=%s\n", port);
    if (retries) {
        int r = atoi(retries);
        if (r < 0) r = 0;
        printf("TRK-v9-retries=%d\n", r);
    }
    if (timeout) printf("TRK-v9-timeout=%s\n", timeout);

    return 0;
}
EOF
    gcc -O3 /app/oracle_tracker.c -o /app/oracle_tracker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
