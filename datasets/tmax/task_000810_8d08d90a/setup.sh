#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    mkdir -p /home/user

    # Create the C source for the encryptor
    cat << 'EOF' > /tmp/encryptor.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/ptrace.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // Simple anti-debugging
    if (ptrace(PTRACE_TRACEME, 0, 1, 0) < 0) {
        printf("Debugger detected!\n");
        return 1;
    }

    if (argc != 3) {
        printf("Usage: %s <input_file> <output_file>\n", argv[0]);
        return 1;
    }

    char *secret_key = "R3dT3am_Pr0c_L3ak_9912"; 

    pid_t pid = fork();
    if (pid == 0) {
        // Sleep to allow the exploit script to reliably read /proc/<pid>/cmdline
        sleep(2);
        char *args[] = {"openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "10000", "-k", secret_key, "-in", argv[1], "-out", argv[2], NULL};
        execvp("openssl", args);
    } else {
        wait(NULL);
    }
    return 0;
}
EOF

    # Compile the binary
    gcc /tmp/encryptor.c -o /home/user/encryptor
    rm /tmp/encryptor.c

    # Create target.enc
    SECRET_KEY="R3dT3am_Pr0c_L3ak_9912"
    FLAG="FLAG{pr0c_cmdl1n3_l34k5_4r3_f4t4l}"
    echo -n "$FLAG" > /tmp/flag_plain.txt
    openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -k "$SECRET_KEY" -in /tmp/flag_plain.txt -out /home/user/target.enc
    rm /tmp/flag_plain.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
