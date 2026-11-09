#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3
    pip3 install pytest

    mkdir -p /home/user/project

    # Broken Makefile
    cat << 'EOF' > /home/user/project/Makefile
CC=gcc
CFLAGS=-Wall -Werror

build: sanitizer.c
	$(CC) $(CFLAGS) -o sanitizer sanitizer.c

clean:
	rm -f sanitizer
EOF

    # Broken C Code (missing <stdio.h> and <string.h>)
    cat << 'EOF' > /home/user/project/sanitizer.c
int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *str = argv[1];
    for (int i = 0; i < strlen(str); i++) {
        if (str[i] == '<' || str[i] == '>') {
            str[i] = '_';
        }
    }
    printf("%s\n", str);
    return 0;
}
EOF

    # Initial SQLite Database
    sqlite3 /home/user/logs.db "CREATE TABLE access_logs (id INTEGER PRIMARY KEY, payload TEXT);"
    sqlite3 /home/user/logs.db "INSERT INTO access_logs (payload) VALUES ('<script>alert(1)</script>');"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
