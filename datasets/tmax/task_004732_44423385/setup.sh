#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/proc_dump/1001
mkdir -p /home/user/proc_dump/1002
mkdir -p /home/user/proc_dump/1003
mkdir -p /home/user/proc_dump/1004
mkdir -p /home/user/proc_dump/1005
mkdir -p /home/user/proc_dump/1006
mkdir -p /home/user/web_app/js
mkdir -p /home/user/web_app/css

# Create fake cmdline files (null-byte separated)
printf "python\0server.py\0--port=8080\0" > /home/user/proc_dump/1001/cmdline
printf "node\0worker.js\0--secret-token=alpha_99x_abc\0" > /home/user/proc_dump/1002/cmdline
printf "bash\0backup.sh\0" > /home/user/proc_dump/1003/cmdline
printf "./binary\0--secret-token=beta_42y_def\0--daemon\0" > /home/user/proc_dump/1004/cmdline
printf "sleep\01000\0" > /home/user/proc_dump/1005/cmdline
printf "ruby\0task.rb\0--secret-token=gamma_11z_ghi\0" > /home/user/proc_dump/1006/cmdline

# Create encryption key
echo -n "SuperSecureAuditKey2024!" > /home/user/audit.key

# Create web app files
echo "<html><body>Hello</body></html>" > /home/user/web_app/index.html
echo "console.log('init');" > /home/user/web_app/js/app.js
echo "body { color: black; }" > /home/user/web_app/css/style.css
echo "function util() {}" > /home/user/web_app/js/utils.js

# Generate manifest
cd /home/user/web_app
sha256sum index.html js/app.js css/style.css js/utils.js > /home/user/manifest.sha256
cd /home/user

# Tamper with files
echo "console.log('hacked');" >> /home/user/web_app/js/app.js
rm /home/user/web_app/css/style.css

# Create trusted domains
cat << 'EOF' > /home/user/trusted_domains.txt
https://api.example.com
https://cdn.example.com
https://analytics.example.com
EOF

chown -R user:user /home/user/*
chmod -R 777 /home/user
