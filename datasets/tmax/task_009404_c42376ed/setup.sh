#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc binutils procps
    pip3 install pytest

    mkdir -p /home/user

    # Create the dummy target executable that sleeps briefly to simulate a short-lived process
    cat << 'EOF' > /home/user/dummy_cmd
#!/bin/bash
sleep 0.5
EOF
    chmod +x /home/user/dummy_cmd

    # Create the background worker script that leaks the token
    cat << 'EOF' > /home/user/cron_worker.sh
#!/bin/bash
while true; do
    /home/user/dummy_cmd --token a8f5f167f44f4964e6c998dee827110c &
    sleep 1.5
done
EOF
    chmod +x /home/user/cron_worker.sh

    # Create the C source for the validator and compile it to an ELF binary
    cat << 'EOF' > /home/user/validator.c
#include <stdio.h>
#include <string.h>

const char* EXPECTED_HASH = "a8f5f167f44f4964e6c998dee827110c";
const char* SALT = "Kx9!";

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <hash>\n", argv[0]);
        return 1;
    }

    // Obfuscate the salt usage slightly to prevent direct grep without looking
    char salt_buffer[10];
    strcpy(salt_buffer, SALT);

    if (strcmp(argv[1], EXPECTED_HASH) == 0) {
        printf("Valid token.\n");
        return 0;
    } else {
        printf("Invalid token.\n");
        return 1;
    }
}
EOF
    gcc /home/user/validator.c -o /home/user/validator
    strip /home/user/validator
    rm /home/user/validator.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
