#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    mkdir -p /home/user/tools

    cat << 'EOF' > /home/user/docs.conf
PREFIX=LIB_DOC
EOF

    cat << 'EOF' > /home/user/src/module_a.c
#include <stdio.h>

/* API
name: module_a_init
desc: Initializes module A
*/
void module_a_init() {
    printf("Init A\n");
}

/* Internal
This is not an API block.
*/
EOF

    cat << 'EOF' > /home/user/src/module_b.c
#include <stdlib.h>

/* API
name: module_b_run
desc: Runs the main loop for module B
args: none
*/
void module_b_run() {
    // do nothing
}
EOF

    cat << 'EOF' > /home/user/tools/safe_append.c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    int fd = open(argv[1], O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return 1;

    // TODO: Add exclusive file lock here

    char buffer[1024];
    ssize_t bytes_read;
    while ((bytes_read = read(STDIN_FILENO, buffer, sizeof(buffer))) > 0) {
        write(fd, buffer, bytes_read);
    }

    // TODO: Unlock file here

    close(fd);
    return 0;
}
EOF

    chmod -R 777 /home/user
