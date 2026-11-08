#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit/logs

    cat << 'EOF' > /home/user/audit/http_traffic.dump
HTTP/1.1 200 OK
Date: Wed, 21 Oct 2023 07:28:00 GMT
Server: Apache/2.4.41 (Ubuntu)
Set-Cookie: session=sec_tok_9981245abc; Path=/; Secure; HttpOnly
Content-Length: 124
Content-Type: text/html; charset=UTF-8

<html><body>Log accessed successfully.</body></html>
EOF

    echo "Tampered log entry 1" > /home/user/audit/logs/log_01.txt
    echo "Authentic log entry 2" > /home/user/audit/logs/log_02.txt
    echo "Tampered log entry 3" > /home/user/audit/logs/log_03.txt

    sha256sum /home/user/audit/logs/log_02.txt | awk '{print $1}' > /home/user/audit/checksum.txt

    cat << 'EOF' > /home/user/audit/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <output_file>\n", argv[0]);
        return 1;
    }

    // Vulnerability: CWE-732 - Hardcoded 0777 permissions
    int fd = open(argv[1], O_CREAT | O_WRONLY | O_TRUNC, 0777);
    if (fd < 0) {
        perror("Failed to open file");
        return 1;
    }

    char *data = "Log summary data\n";
    write(fd, data, 17);
    close(fd);

    printf("Successfully wrote to %s\n", argv[1]);
    return 0;
}
EOF

    chown -R user:user /home/user/audit
    chmod -R 777 /home/user
