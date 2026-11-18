#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat g++ systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/systemd/user/

    cat << 'EOF' > /home/user/backend-mailer.sh
#!/bin/bash
socat TCP-LISTEN:2525,fork,reuseaddr SYSTEM:"cat >> /home/user/mail_spool.log"
EOF
    chmod +x /home/user/backend-mailer.sh

    cat << 'EOF' > /home/user/.config/systemd/user/backend-mailer.service
[Unit]
Description=Backend Mailer Spool

[Service]
ExecStart=/home/user/backend-mailer.sh
Restart=always

[Install]
WantedBy=default.target
EOF

    cat << 'EOF' > /home/user/mailer_app.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>

int main() {
    int sock = 0;
    struct sockaddr_in serv_addr;

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        std::cerr << "Socket creation error" << std::endl;
        return -1;
    }

    serv_addr.sin_family = AF_INET;
    // BUG: Connects to 10024 instead of 10025
    serv_addr.sin_port = htons(10024); 

    if (inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        std::cerr << "Invalid address/ Address not supported" << std::endl;
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cerr << "Connection Failed" << std::endl;
        return -1;
    }

    std::string payload = "HELO local\nMAIL FROM:<test@local>\nRCPT TO:<admin@local>\nDATA\nSTATUS: FIXED\n.\n";
    send(sock, payload.c_str(), payload.length(), 0);
    close(sock);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/mailer_app.service
[Unit]
Description=Mailer App

[Service]
Type=oneshot
ExecStart=/home/user/mailer_app

[Install]
WantedBy=default.target
EOF

    chmod -R 777 /home/user
