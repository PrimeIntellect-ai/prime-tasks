#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ acl libacl1-dev curl systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs /home/user/raw_config /home/user/proxy_config /home/user/scripts /home/user/src /home/user/bin /home/user/www
    mkdir -p /home/user/.config/systemd/user/

    echo "Hello from backend!" > /home/user/www/index.html

    cat << 'EOF' > /home/user/logs/backend_startup.log
[INFO] Server app1 initialized
[INFO] Server app1 started successfully at 127.0.0.1:9001
[ERROR] Server app2 failed to bind
[INFO] DB connection established
EOF

    cat << 'EOF' > /home/user/scripts/extract_backends.sh
#!/bin/bash
grep "started successfully" /home/user/logs/backend_startup.log | awk '{print $2}' > /home/user/raw_config/backends.conf
EOF
    chmod +x /home/user/scripts/extract_backends.sh

    cat << 'EOF' > /home/user/scripts/fstab.proxy
/home/user/raw_config /home/user/proxy_config bindfs broken_options 0 0
EOF

    cat << 'EOF' > /home/user/scripts/mount_config.sh
#!/bin/bash
# Mocking mount behavior for user-space without sudo. 
# Reads fstab.proxy and copies/binds data.
OPTS=$(cat /home/user/scripts/fstab.proxy | awk '{print $3}')
if [ "$OPTS" != "bind" ]; then
    echo "Error: fstab must use 'bind' as the filesystem/option type."
    exit 1
fi
# Simulate bind mount in user space using a symlink or cp for the test environment
cp -r /home/user/raw_config/* /home/user/proxy_config/
EOF
    chmod +x /home/user/scripts/mount_config.sh

    cat << 'EOF' > /home/user/src/proxy.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/acl.h>
#include <acl/libacl.h>

bool check_acl(const std::string& filepath) {
    acl_t acl = acl_get_file(filepath.c_str(), ACL_TYPE_ACCESS);
    if (!acl) return false;
    char* text = acl_to_text(acl, NULL);
    std::string acl_str(text);
    acl_free(text);
    acl_free(acl);
    return acl_str.find("nobody") != std::string::npos;
}

int main() {
    if (!check_acl("/home/user/proxy_config/backends.conf")) {
        std::cerr << "ACL check failed. nobody does not have access.\n";
        return 1;
    }

    std::ifstream infile("/home/user/proxy_config/backends.conf");
    std::string backend;
    if (!std::getline(infile, backend)) {
        std::cerr << "No backend found.\n";
        return 1;
    }

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(80); // BUG: Port 80 requires root

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        std::cerr << "Bind failed\n";
        return 1;
    }

    listen(server_fd, 3);

    // Minimal mock response to act like a proxy since writing a full C++ reverse proxy is too long
    // Instead of actually forwarding, it just returns a fixed response indicating success 
    // or calls curl internally for simplicity in this mock.
    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        std::string resp = "HTTP/1.1 200 OK\nContent-Type: text/plain\n\nHello from backend!\n";
        send(new_socket, resp.c_str(), resp.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/proxy-manager.service
[Unit]
Description=C++ Proxy Manager

[Service]
Type=simple
ExecStart=/home/user/bin/proxy
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    chmod -R 777 /home/user
