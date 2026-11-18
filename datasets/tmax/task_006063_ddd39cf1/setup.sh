#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils xxd coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the C source for the decoder
    cat << 'EOF' > decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    int len = strlen(hex);
    for (int i = 0; i < len; i += 2) {
        char byte_str[3] = {hex[i], hex[i+1], '\0'};
        int byte = (int)strtol(byte_str, NULL, 16);
        putchar(byte ^ 0x42);
    }
    putchar('\n');
    return 0;
}
EOF

    # Compile and strip
    gcc -O2 decoder.c -o decoder
    strip decoder
    rm decoder.c

    # Create raw_data.txt
    cat << 'EOF' > raw_data.txt
Az4oJw==
IAw7Ljg=
IQo3LAo+Hg==
JgwrKjc=
HwovJw==
Hj4/KDA+Kg==
JT4uHw==
Cg8rHgwu
KzYnKjE=
LzYqKjE+Kw==
EOF

    # Create buggy bash script
    cat << 'EOF' > process_data.sh
#!/bin/bash
rm -f /home/user/final_output.txt
rm -f /home/user/tmp.out

while read -r word; do
    hex=$(echo -n "$word" | base64 -d | xxd -p | tr -d '\n')
    # RACE CONDITION: All background jobs write to the same tmp file concurrently
    ./decoder "$hex" > /home/user/tmp.out &
    cat /home/user/tmp.out >> /home/user/final_output.txt
done < /home/user/raw_data.txt
wait
EOF
    chmod +x process_data.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
