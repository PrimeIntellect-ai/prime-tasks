#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /app/libloc-0.1.0
cat << 'EOF' > /app/libloc-0.1.0/Makefile
CC=nonexistent-gcc-99
CFLAGS=-I.

libloc.a: loc.o
	ar rcs libloc.a loc.o

loc.o: loc.c loc.h
	$(CC) $(CFLAGS) -c loc.c -o loc.o
EOF

cat << 'EOF' > /app/libloc-0.1.0/loc.h
#ifndef LOC_H
#define LOC_H
void normalize_whitespace(char *str);
#endif
EOF

cat << 'EOF' > /app/libloc-0.1.0/loc.c
#include "loc.h"
#include <ctype.h>
#include <string.h>

void normalize_whitespace(char *str) {
    if (!str) return;
    int i = 0, j = 0;
    int space_flag = 0;
    while (isspace((unsigned char)str[i])) i++;
    while (str[i] != '\0') {
        if (isspace((unsigned char)str[i])) {
            if (!space_flag) { str[j++] = ' '; space_flag = 1; }
        } else {
            str[j++] = str[i];
            space_flag = 0;
        }
        i++;
    }
    if (j > 0 && str[j-1] == ' ') j--;
    str[j] = '\0';
}
EOF

mkdir -p /home/user /opt/eval
cat << 'EOF' > /home/user/base_en.csv
BTN_OK,    Ok  
BTN_CANCEL,Cancel
MSG_HELLO,  Hello    World
ERR_404, Not   Found
EOF

cat << 'EOF' > /home/user/updates_fr.csv
BTN_OK,D'accord
MSG_HELLO,Bonjour le monde
EOF

# Use sed to avoid Apptainer template variable parsing errors
cat << 'EOF' > /home/user/tm_fr.txt
[[BTN_CANCEL]] === {X{Annuler}X}
[[ERR_404]] === {X{Introuvable}X}
[[IGNORE_ME]] === {X{Rien}X}
EOF
sed -i 's/{X{/{{/g' /home/user/tm_fr.txt
sed -i 's/}X}/}}/g' /home/user/tm_fr.txt

cat << 'EOF' > /opt/eval/golden_fr.csv
BTN_OK,D'accord
BTN_CANCEL,Annuler
MSG_HELLO,Bonjour le monde
ERR_404,Introuvable
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
