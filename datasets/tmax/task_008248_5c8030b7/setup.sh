#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install pytest

    mkdir -p /home/user/waf_pr

    cat << 'EOF' > /home/user/waf_pr/ip_trie.h
#ifndef IP_TRIE_H
#define IP_TRIE_H

typedef struct Node {
    char key;
    int is_end;
    struct Node* left;
    struct Node* right;
} Node;

Node* create_node(char key);
void insert(Node* root, const char* str);
void trie_free(Node* root);
void trie_compress(Node* root);
void print_trie(Node* root, char* buffer, int depth);

#endif
EOF

    cat << 'EOF' > /home/user/waf_pr/ip_trie.c
#include <stdlib.h>
#include <stdio.h>
#include "ip_trie.h"

Node* create_node(char key) {
    Node* node = (Node*)malloc(sizeof(Node));
    node->key = key;
    node->is_end = 0;
    node->left = NULL;
    node->right = NULL;
    return node;
}

void insert(Node* root, const char* str) {
    Node* curr = root;
    for (int i = 0; str[i] != '\0'; i++) {
        if (str[i] == '0') {
            if (!curr->left) curr->left = create_node('0');
            curr = curr->left;
        } else {
            if (!curr->right) curr->right = create_node('1');
            curr = curr->right;
        }
    }
    curr->is_end = 1;
}

void trie_free(Node* root) {
    if (!root) return;

    // BUG 1: Use after free and memory leak
    free(root);
    if (root->left) trie_free(root->left);
    if (root->right) trie_free(root->right);
}

void trie_compress(Node* root) {
    // TODO: Implement path compression
    // If a node has exactly one child and is_end == 0, merge it.
    // (For this simplified task, the agent just needs to make it not crash, 
    // but a basic implementation should prune empty paths).
    if (!root) return;
}

void print_trie(Node* root, char* buffer, int depth) {
    if (!root) return;
    buffer[depth] = root->key;
    if (root->is_end) {
        buffer[depth + 1] = '\0';
        printf("%s\n", buffer);
    }
    print_trie(root->left, buffer, depth + 1);
    print_trie(root->right, buffer, depth + 1);
}
EOF

    cat << 'EOF' > /home/user/waf_pr/main.c
#include <stdio.h>
#include <stdlib.h>
#include "ip_trie.h"

int main() {
    Node* root = create_node('R');

    insert(root, "101");
    insert(root, "100");
    insert(root, "111");

    trie_compress(root);

    char buffer[256];
    print_trie(root, buffer, 0);

    trie_free(root);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
