#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        socat \
        netcat-openbsd \
        gawk \
        coreutils \
        sed \
        grep

    pip3 install pytest

    # Create the user and home directory
    useradd -m -s /bin/bash user || true

    # Create the raw_translations.tsv file
    cat << 'EOF' > /home/user/raw_translations.tsv
ID	LangCode	SourceText	ProposedText
101	FR	Hello, user!	Bonjour, user!
102	FR	System error 404!	Erreur system 404!
103	FR	Test config file	Test config fichier
104	FR	Admin login ok	Admin login ok
201	ES	System error 404!	Error system 404!
202	ES	Test config file	Test config archivo
203	ES	Admin login ok	Admin login ok
204	ES	No match	Nada
EOF

    # Create the tqs binary
    mkdir -p /app
    cat << 'EOF' > /tmp/tqs.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_WORDS 1000
#define MAX_LEN 256

int get_words(char *str, char words[MAX_WORDS][MAX_LEN]) {
    int count = 0;
    char *token = strtok(str, " \t\n\r");
    while (token != NULL && count < MAX_WORDS) {
        strcpy(words[count++], token);
        token = strtok(NULL, " \t\n\r");
    }
    return count;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("0.00\n");
        return 1;
    }
    char words1[MAX_WORDS][MAX_LEN];
    char words2[MAX_WORDS][MAX_LEN];
    char str1[8192], str2[8192];
    strncpy(str1, argv[1], 8191); str1[8191] = '\0';
    strncpy(str2, argv[2], 8191); str2[8191] = '\0';

    int n1 = get_words(str1, words1);
    int n2 = get_words(str2, words2);

    char set1[MAX_WORDS][MAX_LEN]; int s1 = 0;
    char set2[MAX_WORDS][MAX_LEN]; int s2 = 0;

    for(int i=0; i<n1; i++) {
        int dup = 0;
        for(int j=0; j<s1; j++) { if(strcmp(words1[i], set1[j])==0) {dup=1; break;} }
        if(!dup) strcpy(set1[s1++], words1[i]);
    }
    for(int i=0; i<n2; i++) {
        int dup = 0;
        for(int j=0; j<s2; j++) { if(strcmp(words2[i], set2[j])==0) {dup=1; break;} }
        if(!dup) strcpy(set2[s2++], words2[i]);
    }

    int inter = 0;
    for(int i=0; i<s1; i++) {
        for(int j=0; j<s2; j++) {
            if(strcmp(set1[i], set2[j])==0) { inter++; break; }
        }
    }
    int union_sz = s1 + s2 - inter;
    if (union_sz == 0) {
        printf("0.00\n");
    } else {
        printf("%.2f\n", (float)inter / union_sz);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/tqs.c -o /app/tqs
    strip /app/tqs
    rm /tmp/tqs.c
    chmod +x /app/tqs

    # Set permissions
    chmod -R 777 /home/user
