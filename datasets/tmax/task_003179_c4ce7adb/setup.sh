#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gawk netcat-openbsd binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/iptables.rules
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 8194 -m comment --comment "/* auth_service_port */" -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
COMMIT
EOF

cat << 'EOF' > /tmp/auth_service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <port>\n", argv[0]);
        return 1;
    }
    int port = atoi(argv[1]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }
    listen(server_fd, 3);

    int new_socket = accept(server_fd, NULL, NULL);
    char buffer[1024] = {0};
    read(new_socket, buffer, 1024);

    buffer[strcspn(buffer, "\r\n")] = 0; // strip newline

    // Filter input to prevent command injection
    for(int i=0; buffer[i]; i++) {
        if(buffer[i] < '0' || buffer[i] > '9') {
            buffer[i] = '\0';
            break;
        }
    }

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "echo -n '%s' | sha256sum | awk '{print $1}'", buffer);
    FILE *fp = popen(cmd, "r");
    char hash[65] = {0};
    if (fp) {
        fgets(hash, 65, fp);
        pclose(fp);
    }

    // SHA256 hash of "4829"
    const char *target = "2c2621c5b4b1a2bf2a69ab3680e64cd4681db600ccbde724ff0e653842c1ebda";

    if (strcmp(hash, target) == 0) {
        send(new_socket, "FLAG{3lf_4uth_byP4ss_99x}\n", 26, 0);
    } else {
        send(new_socket, "FAIL\n", 5, 0);
    }
    close(new_socket);
    close(server_fd);
    return 0;
}
EOF

gcc /tmp/auth_service.c -o /home/user/auth_service
rm /tmp/auth_service.c

chown user:user /home/user/auth_service
chmod +x /home/user/auth_service
chown user:user /home/user/iptables.rules

chmod -R 777 /home/user
