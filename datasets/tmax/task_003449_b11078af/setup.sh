#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /home/user/audit/sys_files/etc/cron.d
    mkdir -p /home/user/audit/sys_files/usr/local/bin
    mkdir -p /home/user/audit/sys_files/var/log

    touch /home/user/audit/sys_files/etc/cron.d/daily_backup
    touch /home/user/audit/sys_files/usr/local/bin/log_cleaner.sh
    touch /home/user/audit/sys_files/var/log/app.log

    chmod 644 /home/user/audit/sys_files/etc/cron.d/daily_backup
    chmod 755 /home/user/audit/sys_files/usr/local/bin/log_cleaner.sh

    touch /home/user/audit/sys_files/usr/local/bin/helper_script.sh
    chmod 777 /home/user/audit/sys_files/usr/local/bin/helper_script.sh

    cat << 'EOF' > /home/user/audit/target.cpp
#include <iostream>
#include <string>

void authenticate() {
    std::string secret = "X-Admin-Token: sUp3r_S3cr3t_T0k3n_8821";
    std::cout << "Authenticating..." << std::endl;
}

int main() {
    authenticate();
    return 0;
}
EOF
    g++ /home/user/audit/target.cpp -o /home/user/audit/target_binary
    rm /home/user/audit/target.cpp

    cat << 'EOF' > /home/user/audit/http_logs.txt
IP: 192.168.1.15
GET /dashboard HTTP/1.1
Host: internal.corp
Cookie: session_id=abc1234; X-Admin-Token: sUp3r_S3cr3t_T0k3n_8821

IP: 10.0.0.55
GET /profile HTTP/1.1
Host: internal.corp
Cookie: session_id=xyz9876; lang=en

IP: 172.16.4.102
POST /api/config HTTP/1.1
Host: internal.corp
Cookie: X-Admin-Token: sUp3r_S3cr3t_T0k3n_8821; region=us-east

IP: 192.168.1.200
GET /login HTTP/1.1
Host: internal.corp
Cookie: session_id=none
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
