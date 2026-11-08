#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/staging_backups
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the audio file
    espeak -w /app/incident_report.wav "The system is down. The Target Restore ID is bravo seven niner."

    # Python script to generate the tarballs
    cat << 'EOF' > /tmp/gen_tarballs.py
import tarfile
import os

os.makedirs('/app/staging_backups', exist_ok=True)
os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

# Create a fake disk image
with open('/tmp/disk.img', 'w') as f:
    f.write('fake disk image content')

# Create a fake start_vm.sh that just starts a python web server serving the expected output
with open('/tmp/start_vm.sh', 'w') as f:
    f.write('''#!/bin/bash
python3 -c "
import http.server
import socketserver
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'SYSTEM_RESTORE_SUCCESS_TOKEN_99812\n')
socketserver.TCPServer(('', 8080), Handler).serve_forever()
" &
sleep 1
''')
os.chmod('/tmp/start_vm.sh', 0o755)

# Staging backups
with tarfile.open('/app/staging_backups/backup_bravo79.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/disk.img', arcname='disk.img')
    tar.add('/tmp/start_vm.sh', arcname='start_vm.sh')

with open('/tmp/dummy.txt', 'wb') as f:
    f.write(b'dummy')

with tarfile.open('/app/staging_backups/backup_alpha12.tar.gz', 'w:gz') as tar:
    ti = tarfile.TarInfo('../evil.txt')
    ti.size = 5
    tar.addfile(ti, open('/tmp/dummy.txt', 'rb'))

with tarfile.open('/app/staging_backups/backup_delta44.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/dummy.txt', arcname='dummy.txt')

# Corpora
for i in range(5):
    with tarfile.open(f'/app/corpora/clean/clean_{i}.tar.gz', 'w:gz') as tar:
        tar.add('/tmp/dummy.txt', arcname=f'dummy_{i}.txt')

for i in range(5):
    with tarfile.open(f'/app/corpora/evil/evil_{i}.tar.gz', 'w:gz') as tar:
        if i == 0:
            ti = tarfile.TarInfo('/etc/shadow')
        elif i == 1:
            ti = tarfile.TarInfo('../../root/ssh')
        elif i == 2:
            ti = tarfile.TarInfo('setuid_file')
            ti.mode = 0o4755
        elif i == 3:
            ti = tarfile.TarInfo('setgid_file')
            ti.mode = 0o2755
        else:
            ti = tarfile.TarInfo('/absolute/path')
        ti.size = 5
        tar.addfile(ti, open('/tmp/dummy.txt', 'rb'))
EOF

    python3 /tmp/gen_tarballs.py
    rm /tmp/gen_tarballs.py /tmp/disk.img /tmp/start_vm.sh /tmp/dummy.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
