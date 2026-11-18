#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/web-app
    cd /home/user/web-app

    cat << 'EOF' > url_parser.h
#ifndef URL_PARSER_H
#define URL_PARSER_H
void parse_url_params(const char* query, char* key1, char* val1, char* key2, char* val2);
#endif
EOF

    cat << 'EOF' > url_parser.c
#include <string.h>
#include "url_parser.h"

void parse_url_params(const char* query, char* key1, char* val1, char* key2, char* val2) {
    // Highly simplified and unsafe parser for task purposes
    char temp[256];
    strncpy(temp, query, 255);

    char* token1 = strtok(temp, "&");
    char* token2 = strtok(NULL, "&");

    if (token1) {
        char* eq = strchr(token1, '=');
        if (eq) {
            *eq = '\0';
            strcpy(key1, token1);
            strcpy(val1, eq + 1);
        }
    }
    if (token2) {
        char* eq = strchr(token2, '=');
        if (eq) {
            *eq = '\0';
            strcpy(key2, token2);
            strcpy(val2, eq + 1);
        }
    }
}
EOF

    cat << 'EOF' > json_serializer.h
#ifndef JSON_SERIALIZER_H
#define JSON_SERIALIZER_H
void serialize_to_json(const char* k1, const char* v1, const char* k2, const char* v2, char* output);
#endif
EOF

    cat << 'EOF' > json_serializer.c
#include <stdio.h>
#include "json_serializer.h"

void serialize_to_json(const char* k1, const char* v1, const char* k2, const char* v2, char* output) {
    sprintf(output, "{\"%s\":\"%s\",\"%s\":\"%s\"}", k1, v1, k2, v2);
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include "url_parser.h"
#include "json_serializer.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char k1[64]={0}, v1[64]={0}, k2[64]={0}, v2[64]={0};
    char json_out[256]={0};

    parse_url_params(argv[1], k1, v1, k2, v2);
    serialize_to_json(k1, v1, k2, v2, json_out);

    printf("%s", json_out);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall -Wextra

cgi_bin: main.o url_parser.o json_serializer.o
	$(CC) $(CFLAGS) main.o url_parser.o -o cgi_bin

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

url_parser.o: url_parser.c
	$(CC) $(CFLAGS) -c url_parser.c

json_serializer.o: json_serializer.c
	$(CC) $(CFLAGS) -c json_serializer.c

clean:
	rm -f *.o cgi_bin
EOF

    cp Makefile Makefile.orig

    chmod -R 777 /home/user
