#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make openssh-server openssh-client gawk grep
    pip3 install pytest

    mkdir -p /app/backup_data
    mkdir -p /app/libnetconf
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/backup_data/manifest.txt
2023-01-01 10:00:00 RESTORED rule_A
2023-01-02 11:00:00 FAILED rule_B
2023-01-03 12:00:00 RESTORED rule_C
EOF

    cat << 'EOF' > /app/libnetconf/net_parse.c
#include <stdio.h>
/* Missing #include <arpa/inet.h> */
int net_parse_rule(const char* rule) {
    return 0;
}
EOF

    cat << 'EOF' > /app/libnetconf/Makefile
all: net_parse.c
	gcc -o libnetconf.a net_parse.c
EOF

    cat << 'EOF' > /opt/oracle/oracle.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>

int main() {
    char buf[256];
    if (fgets(buf, sizeof(buf), stdin)) {
        if (strncmp(buf, "ROUTE:", 6) == 0) {
            if (isdigit(buf[6]) && isdigit(buf[7]) && isdigit(buf[8]) && isdigit(buf[9]) && buf[10] == '.' && isupper(buf[11])) {
                printf("VALID\n");
                return 0;
            }
        }
    }
    printf("INVALID\n");
    return 0;
}
EOF
    gcc -o /opt/oracle/validate_ip_format_oracle /opt/oracle/oracle.c
    chmod +x /opt/oracle/validate_ip_format_oracle

    useradd -m -s /bin/bash user || true

    mkdir -p /run/sshd
    ssh-keygen -A
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys
    chown -R user:user /home/user/.ssh

    chmod -R 777 /home/user
