#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx openssh-server
    pip3 install pytest

    # Create directories
    mkdir -p /app/reference_oracle
    mkdir -p /home/user/workspace
    mkdir -p /home/user/nginx
    mkdir -p /home/user/ssh
    mkdir -p /home/user/.ssh
    mkdir -p /run/sshd

    # Create reference oracle source and compile
    cat << 'EOF' > /app/reference_oracle/oracle.cpp
#include <iostream>
#include <string>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::string input = argv[1];
    std::string key = "AUDIT_COMPLIANCE_2024";
    for (size_t i = 0; i < input.length(); ++i) {
        unsigned char c = input[i] ^ key[i % key.length()];
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)c;
    }
    std::cout << std::endl;
    return 0;
}
EOF
    g++ -o /app/reference_oracle/audit_tokenizer /app/reference_oracle/oracle.cpp
    rm /app/reference_oracle/oracle.cpp
    chmod +x /app/reference_oracle/audit_tokenizer

    # Create basic nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        server_name localhost;
        location / {
            return 200 "OK\n";
        }
    }
}
EOF

    # Create basic sshd config
    cat << 'EOF' > /home/user/ssh/sshd_config
Port 2222
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
PasswordAuthentication yes
EOF

    # Create start services script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /home/user/nginx/nginx.conf
/usr/sbin/sshd -f /home/user/ssh/sshd_config
EOF
    chmod +x /app/start_services.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
