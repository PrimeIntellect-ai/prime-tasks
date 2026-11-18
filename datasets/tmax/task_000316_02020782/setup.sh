#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        // remove newline
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') buffer[len-1] = '\0';

        long sum = 0;
        for (int i = 0; i < strlen(buffer); i++) {
            sum += buffer[i];
        }

        for (int i = 0; i < 20; i++) {
            float val = (float)((sum * (i + 1)) % 100) / 100.0f;
            printf("%.4f", val);
            if (i < 19) printf(" ");
        }
        printf("\n");
    }
    return 0;
}
EOF
    gcc -O3 -s /tmp/oracle.c -o /app/tokenizer_oracle
    chmod +x /app/tokenizer_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
