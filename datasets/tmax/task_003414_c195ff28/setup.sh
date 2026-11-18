#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/audit_data
cat << 'EOF' > /home/user/audit_data/source_code.txt
void login(std::string user) {
    std::string query = "SELECT * FROM users WHERE user = '" + user + "'";
    db.execute(query);
}

void profile(std::string name) {
    std::string html = "<h1>Welcome, " + name + "</h1>";
    response.send(html);
}

void clean_query() {
    std::string query = "SELECT * FROM users WHERE id = ?";
    db.execute(query, id);
}
EOF

cat << 'EOF' > /home/user/audit_data/auth.log
192.168.1.10 - FAILED LOGIN
192.168.1.10 - FAILED LOGIN
10.0.0.5 - SUCCESS LOGIN
192.168.1.10 - FAILED LOGIN
192.168.1.10 - FAILED LOGIN
172.16.0.4 - FAILED LOGIN
172.16.0.4 - FAILED LOGIN
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
