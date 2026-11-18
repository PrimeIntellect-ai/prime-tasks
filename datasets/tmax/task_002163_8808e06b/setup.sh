#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/hidden_corpus/clean /app/hidden_corpus/evil

    cat << 'EOF' > /tmp/differ.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    char buffer[4096];
    int has_bad_xml = 0;
    int has_bad_json = 0;

    while (fgets(buffer, sizeof(buffer), stdin)) {
        if (strstr(buffer, "<retry_policy>infinite</retry_policy>")) has_bad_xml = 1;
        if (strstr(buffer, "\"force_duplicate_on_retry\": true")) has_bad_json = 1;
    }

    if (has_bad_xml && has_bad_json) {
        printf("DUPLICATE_RETRY_ERROR\n");
        return 139;
    }
    printf("OK\n");
    return 0;
}
EOF

    gcc -O2 -s -o /app/config_differ /tmp/differ.c
    rm /tmp/differ.c

    cat << 'EOF' > /tmp/gen_corpus.py
import os

def create_files(base_dir, num_files, is_evil):
    os.makedirs(base_dir, exist_ok=True)
    for i in range(num_files):
        with open(os.path.join(base_dir, f"config_{i}.txt"), "w") as f:
            f.write("{\n  \"metadata\": \"test\"\n}\n")
            if is_evil:
                f.write("<retry_policy>infinite</retry_policy>\n")
                f.write("\"force_duplicate_on_retry\": true\n")
            else:
                if i % 3 == 0:
                    f.write("<retry_policy>infinite</retry_policy>\n")
                elif i % 3 == 1:
                    f.write("\"force_duplicate_on_retry\": true\n")
                else:
                    f.write("<retry_policy>normal</retry_policy>\n")

create_files("/app/corpus/clean", 10, False)
create_files("/app/corpus/evil", 10, True)
create_files("/app/hidden_corpus/clean", 10, False)
create_files("/app/hidden_corpus/evil", 10, True)
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
