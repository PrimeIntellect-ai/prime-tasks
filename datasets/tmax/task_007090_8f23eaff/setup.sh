#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/rle.cpp
void rle_encode(const char* input, char* output, int max_out_len) {
    int i = 0;
    int j = 0;
    while (input[i] != '\0') {
        int count = 1;
        while (input[i] == input[i+1] && count < 9) { // count < 9 keeps it to a single digit
            count++;
            i++;
        }
        output[j++] = input[i];
        output[j++] = count + '0';
        i++;
    }
    output[j] = '\0';
}
EOF

    chmod -R 777 /home/user
