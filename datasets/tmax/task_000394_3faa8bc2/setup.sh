#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y nginx g++ make spawn-fcgi curl libfcgi-dev locales systemd

    # Setup locales
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8

    # Create Nginx config
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    location /api {
        fastcgi_pass 127.0.0.1:9000;
        include fastcgi_params;
    }
}
EOF

    # Create oracle program
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
using namespace std;
int main() {
    string s;
    if (!(cin >> s)) return 0;
    if (s.empty()) return 0;
    char c = s[0];
    int count = 1;
    for (size_t i = 1; i < s.length(); ++i) {
        if (s[i] == c) count++;
        else { cout << c << count; c = s[i]; count = 1; }
    }
    cout << c << count << endl;
    return 0;
}
EOF
    g++ -O2 /tmp/oracle.cpp -o /opt/oracle_transform
    chmod +x /opt/oracle_transform

    # Create vendored package
    mkdir -p /app/lib-string-transform-1.2.0
    cat << 'EOF' > /app/lib-string-transform-1.2.0/main.cpp
#include <iostream>
#include <string>
#include <locale>
#include <cstdlib>
using namespace std;
int main() {
    try {
        if (locale("").name() != "en_US.UTF-8") {
            return 1;
        }
    } catch (...) {
        return 1;
    }
    string s;
    if (!(cin >> s)) return 0;
    if (s.empty()) return 0;
    char c = s[0];
    int count = 1;
    for (size_t i = 1; i < s.length(); ++i) {
        if (s[i] == c) {
            count++;
            if (count == 10) count = 0; // BUG
        }
        else { cout << c << count; c = s[i]; count = 1; }
    }
    cout << c << count << endl;
    return 0;
}
EOF

    cat << 'EOF' > /app/lib-string-transform-1.2.0/Makefile
CXX = /usr/bin/false
transform_backend: main.cpp
	$(CXX) -O2 main.cpp -o transform_backend
EOF

    # Ensure Nginx runs on shell start for tests
    echo "service nginx start >/dev/null 2>&1 || true" >> /etc/bash.bashrc

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup systemd user directory
    mkdir -p /home/user/.config/systemd/user

    chmod -R 777 /home/user
    chmod -R 777 /app
