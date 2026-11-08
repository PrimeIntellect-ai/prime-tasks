#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev netcat-openbsd expect
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/groups.txt
bob:users
alice:migrators
charlie:admins
david:migrators
EOF

    cat << 'EOF' > /home/user/app_fw.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

// Agent needs to implement this function
int check_group(const char* username) {
    // START MISSING IMPLEMENTATION
    // END MISSING IMPLEMENTATION
    return 0; // Default deny
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(7777);

    // Artificial delay to simulate initialization and cause the race condition
    sleep(2);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            exit(EXIT_FAILURE);
        }

        char buffer[1024] = {0};
        send(new_socket, "Username: ", 10, 0);
        int valread = read(new_socket, buffer, 1024);
        if (valread > 0) {
            // Trim newline
            buffer[strcspn(buffer, "\r\n")] = 0;
            if (check_group(buffer)) {
                send(new_socket, "TOKEN: MIGRATION_AUTH_994827\n", 29, 0);
            } else {
                send(new_socket, "Access Denied\n", 14, 0);
            }
        }
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/start.sh
#!/bin/bash
/home/user/app_fw &
FW_PID=$!

# The agent needs to insert a wait loop here.
# For example: while ! nc -z localhost 7777; do sleep 0.1; done

expect /home/user/test_fw.exp

kill $FW_PID
EOF
    chmod +x /home/user/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
