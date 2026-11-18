#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/audit/code
mkdir -p /home/user/audit/certs
mkdir -p /home/user/audit/firewall

# 1. Permissions setup
echo "safe" > /home/user/audit/code/safe_script.py
echo "unsafe config" > /home/user/audit/code/config_local.json
echo "cache data" > /home/user/audit/code/cache_tmp.txt

# 2. Certificates setup
cd /home/user/audit/certs
openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.pem -days 365 -nodes -subj "/CN=AuditCA"
openssl req -newkey rsa:2048 -keyout leaf1.key -out leaf1.csr -nodes -subj "/CN=ValidLeaf1"
openssl x509 -req -in leaf1.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out leaf1.pem -days 365
openssl req -newkey rsa:2048 -keyout leaf2.key -out leaf2.csr -nodes -subj "/CN=ValidLeaf2"
openssl x509 -req -in leaf2.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out leaf2.pem -days 365
openssl req -x509 -newkey rsa:2048 -keyout leaf3.key -out leaf3.pem -days 365 -nodes -subj "/CN=InvalidLeaf"

# 3. Vulnerability setup
cat << 'EOF' > /home/user/audit/code/auth.php
<?php
// safe
$user = htmlspecialchars($_POST['user']);
echo "Hello " . $user;
?>
EOF

cat << 'EOF' > /home/user/audit/code/search.php
<?php
// XSS vulnerable
$query = $_GET['q'];
echo "<div>Results for: " . $query . "</div>";
?>
EOF

cat << 'EOF' > /home/user/audit/code/app.js
// Safe DOM manipulation
document.getElementById('out').innerText = window.location.hash;
EOF

# 4. Firewall setup
cat << 'EOF' > /home/user/audit/firewall/iptables.rules
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
-A INPUT -s 10.0.0.0/8 -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 3306 -j ACCEPT
COMMIT
EOF

chown -R user:user /home/user/audit

chmod -R 777 /home/user
chmod 644 /home/user/audit/code/safe_script.py
chmod 666 /home/user/audit/code/config_local.json
chmod 777 /home/user/audit/code/cache_tmp.txt
