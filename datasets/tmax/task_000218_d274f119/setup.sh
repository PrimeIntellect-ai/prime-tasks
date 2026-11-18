#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server build-essential
    pip3 install pytest

    mkdir -p /app
    mkdir -p /var/run/sshd

    # Configure SSH server
    echo 'Port 2222' >> /etc/ssh/sshd_config
    useradd -m -s /bin/bash admin
    echo 'admin:siteadmin' | chpasswd

    # Create Python quota service
    cat << 'EOF' > /app/quota_service.py
import socket
import hashlib
import threading
import sys

def handle_client(conn):
    try:
        conn.sendall(b"Enter username: ")
        username = conn.recv(1024).decode().strip()
        conn.sendall(b"Enter password: ")
        password = conn.recv(1024).decode().strip()
        if password == "querypass":
            h = int(hashlib.md5(username.encode()).hexdigest(), 16)
            used = h % 1000000
            limit = (h % 1000000) + 1000000
            conn.sendall(f"QUOTA {used} {limit}\n".encode())
        else:
            conn.sendall(b"ERROR\n")
    except:
        pass
    finally:
        conn.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 9090))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle_client, args=(conn,)).start()

if __name__ == "__main__":
    main()
EOF

    # Create Oracle C++ source
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>

int main() {
    std::string username;
    if (!(std::cin >> username)) return 1;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(8080);
    inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        return 1;
    }

    char buffer[1024] = {0};
    read(sock, buffer, 1024);
    std::string user_out = username + "\n";
    send(sock, user_out.c_str(), user_out.length(), 0);

    memset(buffer, 0, sizeof(buffer));
    read(sock, buffer, 1024);
    std::string pass_out = "querypass\n";
    send(sock, pass_out.c_str(), pass_out.length(), 0);

    memset(buffer, 0, sizeof(buffer));
    int n = read(sock, buffer, 1024);
    std::string response(buffer, n);

    if (response.find("QUOTA ") == 0) {
        size_t space1 = response.find(' ', 6);
        std::string used = response.substr(6, space1 - 6);
        std::string limit = response.substr(space1 + 1);
        limit.erase(limit.find_last_not_of(" \n\r\t") + 1);
        std::cout << "[OK] User: " << username << " | Used: " << used << " bytes | Limit: " << limit << " bytes\n";
    }
    close(sock);
    return 0;
}
EOF

    # Compile Oracle
    g++ -O2 /app/oracle.cpp -o /app/oracle_bin
    strip /app/oracle_bin
    rm /app/oracle.cpp

    # Create service startup script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
if ! pgrep -f "/usr/sbin/sshd" > /dev/null; then
    /usr/sbin/sshd
fi
if ! pgrep -f "quota_service.py" > /dev/null; then
    python3 /app/quota_service.py &
fi
EOF
    chmod +x /app/start_services.sh

    echo "/app/start_services.sh" >> /etc/bash.bashrc
    echo "/app/start_services.sh" >> /root/.bashrc

    useradd -m -s /bin/bash user || true
    echo "/app/start_services.sh" >> /home/user/.bashrc
    chmod -R 777 /home/user
