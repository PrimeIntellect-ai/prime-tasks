#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/pentest_target/cgi-bin
mkdir -p /home/user/pentest_target/logs
mkdir -p /home/user/pentest_target/report

# Create the C source and compile to ELF
cat << 'EOF' > /home/user/pentest_target/cgi-bin/process_login.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char query[256];
    // The hardcoded vulnerable query
    const char *sql_template = "SELECT * FROM users WHERE username='%s' AND password='%s'";

    if(argc > 2) {
        sprintf(query, sql_template, argv[1], argv[2]);
        printf("Executing: %s\n", query);
    }
    return 0;
}
EOF

gcc /home/user/pentest_target/cgi-bin/process_login.c -o /home/user/pentest_target/cgi-bin/process_login
chmod 755 /home/user/pentest_target/cgi-bin/process_login
rm /home/user/pentest_target/cgi-bin/process_login.c

# Create the access.log
cat << 'EOF' > /home/user/pentest_target/logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /cgi-bin/process_login?user=alice&pass=secret&SessionID=9a8b7c6d HTTP/1.1" 200 1024
10.0.0.5 - - [10/Oct/2023:14:01:12 -0700] "GET /cgi-bin/process_login?user=admin'%20OR%20'1'%3D'1&pass=foo&SessionID=f4e3d2c1 HTTP/1.1" 200 2048
192.168.1.12 - - [10/Oct/2023:14:05:00 -0700] "GET /cgi-bin/process_login?user=bob&pass=1234&SessionID=11223344 HTTP/1.1" 401 512
172.16.0.4 - - [10/Oct/2023:14:10:05 -0700] "GET /cgi-bin/process_login?user=admin'%20OR%20'1'%3D'1&pass=bar&SessionID=x9y8z7w6 HTTP/1.1" 401 512
10.0.0.9 - - [10/Oct/2023:14:15:22 -0700] "GET /cgi-bin/process_login?user=admin'%20OR%20'1'%3D'1&pass=baz&SessionID=aabbccdd HTTP/1.1" 200 2048
EOF

chown -R user:user /home/user/pentest_target
chmod -R 777 /home/user
