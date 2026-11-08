#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make nginx openssh-server curl sshpass
pip3 install pytest

useradd -m -s /bin/bash devsecops
useradd -m -s /bin/bash user || true

mkdir -p /app/src /app/bin /app/keys
mkdir -p /run/sshd

ssh-keygen -t ed25519 -f /app/keys/ssh_host_ed25519_key -N ""
ssh-keygen -t ed25519 -f /app/keys/devsecops_ed25519 -N ""
ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N "" || true

mkdir -p ~devsecops/.ssh
cat /app/keys/devsecops_ed25519.pub > ~devsecops/.ssh/authorized_keys
chown -R devsecops:devsecops ~devsecops/.ssh
chmod 700 ~devsecops/.ssh
chmod 600 ~devsecops/.ssh/authorized_keys

cat << 'EOF' > /app/src/api.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[4096] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        memset(buffer, 0, 4096);
        read(new_socket, buffer, 4096);

        char user_agent[128];
        char *ua_start = strstr(buffer, "User-Agent: ");
        if (ua_start) {
            ua_start += 12;
            char *ua_end = strstr(ua_start, "\r\n");
            if (ua_end) {
                char temp[4096] = {0};
                strncpy(temp, ua_start, ua_end - ua_start);
                strcpy(user_agent, temp);
            }
        }

        char *response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}\n";
        write(new_socket, response, strlen(response));
        close(new_socket);
    }
    return 0;
}
EOF

cat << 'EOF' > /app/src/Makefile
all:
	gcc api.c -o ../bin/api
EOF

cat << 'EOF' > /app/nginx.conf
daemon off;
events {}
http {
    server {
        listen 8000;
    }
}
EOF

cat << 'EOF' > /app/sshd_config
Port 2222
PasswordAuthentication yes
PermitRootLogin yes
HostKey /etc/ssh/ssh_host_rsa_key
EOF

cat << 'EOF' > /app/start.sh
#!/bin/bash
/usr/sbin/sshd -f /app/sshd_config
/app/bin/api &
nginx -c /app/nginx.conf &
wait
EOF
chmod +x /app/start.sh

cd /app/src && make

echo "devsecops:password" | chpasswd

chmod -R 777 /home/user
chmod -R 777 /app
