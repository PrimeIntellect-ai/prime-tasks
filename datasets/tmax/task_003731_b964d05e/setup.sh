#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Clean payloads
    echo "cmVkaXJlY3RfdXJsPWh0dHBzOi8vYXV0aC5pbnRlcm5hbC1hcHAubG9jYWwvbG9naW4mdG9rZW49dXNlcg==" > /app/corpora/clean/1.txt
    echo "cmVkaXJlY3RfdXJsPWh0dHBzOi8vaW50ZXJuYWwtYXBwLmxvY2FsL2Rhc2hib2FyZA==" > /app/corpora/clean/2.txt

    # Evil payloads
    echo "cmVkaXJlY3RfdXJsPWh0dHBzOi8vZXZpbC1pbnRlcm5hbC1hcHAubG9jYWwvbG9naW4=" > /app/corpora/evil/1.txt
    echo "cmVkaXJlY3RfdXJsPWh0dHBzOi8vYXR0YWNrZXIuY29tXEBpbnRlcm5hbC1hcHAubG9jYWwv" > /app/corpora/evil/2.txt

    # Create dummy vulnerable binary source
    cat << 'EOF' > /app/auth_redirector.c
#include <stdio.h>
#include <string.h>

int check_url(const char* url) {
    const char* suffix = "internal-app.local";
    size_t url_len = strlen(url);
    size_t suf_len = strlen(suffix);
    if (url_len >= suf_len) {
        if (strcmp(url + url_len - suf_len, suffix) == 0) {
            return 1;
        }
    }
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    if (check_url(argv[1])) return 0;
    return 1;
}
EOF

    gcc -O2 /app/auth_redirector.c -o /app/auth_redirector
    strip -s /app/auth_redirector
    rm /app/auth_redirector.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
