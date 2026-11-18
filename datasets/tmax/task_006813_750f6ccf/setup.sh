#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/token_gen

    cat << 'EOF' > /home/user/token_gen/Makefile
all:
    gcc -o token_bin token_algo.c

clean:
    rm -f token_bin
EOF

    cat << 'EOF' > /home/user/token_gen/token_algo.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Node {
    int hash_val;
    struct Node* next;
};

void insert(struct Node** head, int val) {
    struct Node* new_node = (struct Node*)malloc(sizeof(struct Node));
    new_node->hash_val = val;
    // BUG: missing new_node->next assignment, causes segfault later if traversed

    if (*head == NULL) {
        *head = new_node;
    } else {
        struct Node* temp = *head;
        while (temp->next != NULL) {
            temp = temp->next;
        }
        temp->next = new_node;
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <username>\n", argv[0]);
        return 1;
    }

    char* username = argv[1];
    long hash = 0;

    // Missing semicolon here:
    for (int i = 0; i < strlen(username); i++) {
        hash += username[i]
    }

    hash = hash * 17;

#ifdef SECURE_MODE
    hash = hash * 31;
    char* mode = "SEC";
#else
    char* mode = "STD";
#endif

    struct Node* head = NULL;
    insert(&head, hash);

    // This will segfault because new_node->next was not initialized to NULL
    int verify = 0;
    struct Node* curr = head;
    while (curr != NULL) {
        verify += curr->hash_val;
        curr = curr->next;
    }

    printf("TOKEN-%ld-%s\n", hash, mode);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/token_gen/wrapper.py
import sys
import subprocess

def generate_token(username):
    try:
        # Python 2 print
        print "Generating token for user:", username

        proc = subprocess.Popen(['./token_bin', username], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = proc.communicate()

        if proc.returncode != 0:
            print "Error generating token!"
            return

        # In Python 3, out is bytes. String concatenation will fail or look ugly if not decoded.
        token = out.strip()
        print "Generated: " + token

    except Exception, e: # Python 2 exception syntax
        print "Exception occurred:", str(e)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print "Provide a username"
        sys.exit(1)

    generate_token(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
