#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx tar zip curl
pip3 install pytest flask

mkdir -p /app/incoming
mkdir -p /app/extracted

# Create payload files
mkdir -p /tmp/payload
cat << 'EOF' > /tmp/payload/doc1.txt
Intro text.
[GCODE]
G1 X10 Y20
G0 Z5
[/GCODE]
End text.
EOF

cat << 'EOF' > /tmp/payload/doc2.txt
[GCODE]
G1 X50.5 Y10.2
[/GCODE]
EOF

cat << 'EOF' > /tmp/payload/system_config.txt
MALICIOUS OVERWRITE
EOF

# Create zip with zip slip using python
cat << 'EOF' > /tmp/make_zip.py
import zipfile
import os

os.chdir('/tmp/payload')
with zipfile.ZipFile('/app/incoming/payload.zip', 'w') as z:
    z.write('doc1.txt', 'doc1.txt')
    z.write('doc2.txt', 'doc2.txt')
    z.write('system_config.txt', '../system_config.txt')
EOF
python3 /tmp/make_zip.py

# Create tar
cd /app/incoming
tar -cvf docs.tar payload.zip
rm payload.zip

# Create system_config.txt
echo "SAFE_ORIGINAL_CONFIG" > /app/system_config.txt

# Create nginx.conf skeleton
cat << 'EOF' > /app/nginx.conf
worker_processes 1;
daemon off;
error_log /tmp/error.log;
pid /tmp/nginx.pid;

events { 
    worker_connections 1024; 
}

http {
    client_body_temp_path /tmp/client_temp;
    proxy_temp_path       /tmp/proxy_temp_path;
    fastcgi_temp_path     /tmp/fastcgi_temp;
    uwsgi_temp_path       /tmp/uwsgi_temp;
    scgi_temp_path        /tmp/scgi_temp;
    access_log /tmp/access.log;

    server {
        # listen ???
        server_name localhost;

        # location /docs/ {
        #     proxy_pass ???
        # }
    }
}
EOF

# Create app.py skeleton
cat << 'EOF' > /app/app.py
from flask import Flask
app = Flask(__name__)

# @app.route('/docs/<filename>')
# def serve_doc(filename):
#     pass

if __name__ == '__main__':
    # app.run(...)
    pass
EOF

# Create start.sh
cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /app/nginx.conf &
python3 /app/app.py &
wait
EOF
chmod +x /app/start.sh

chmod -R 777 /app
mkdir -p /var/log/nginx /var/lib/nginx /run
chmod -R 777 /var/log/nginx /var/lib/nginx /run

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
