#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc nginx redis-server curl python3-flask python3-redis
pip3 install pytest

mkdir -p /app/nginx /app/corpus/evil /app/corpus/clean /home/user

cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            return 200 "OK";
        }
        # location /upload is missing
    }
}
EOF

cat << 'EOF' > /app/backend.py
import os
import subprocess
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    file_path = '/tmp/uploaded.elf'
    with open(file_path, 'wb') as f:
        f.write(request.data)

    validator = '/home/user/elf_validator'
    if not os.path.exists(validator):
        return "Validator not found", 500

    result = subprocess.run([validator, file_path])

    r.lpush('audit_log', f'Uploaded file tested, exit code {result.returncode}')

    if result.returncode == 0:
        return "Clean", 200
    else:
        return "Evil", 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9090)
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
python3 /app/backend.py &
sleep 2
EOF
chmod +x /app/start_services.sh

cat << 'EOF' > /tmp/dummy.c
int main() { return 0; }
EOF

# Generate clean binaries
for i in 1 2 3 4 5; do
    gcc /tmp/dummy.c -o /app/corpus/clean/clean${i}.elf
done

# Generate evil binaries
# Evil 1: 32-bit ELF (modify EI_CLASS byte)
cp /app/corpus/clean/clean1.elf /app/corpus/evil/evil1.elf
printf "\x01" | dd of=/app/corpus/evil/evil1.elf bs=1 seek=4 count=1 conv=notrunc

# Evil 2: Executable stack
gcc -z execstack /tmp/dummy.c -o /app/corpus/evil/evil2.elf

# Evil 3: RPATH
gcc -Wl,-rpath,/tmp /tmp/dummy.c -o /app/corpus/evil/evil3.elf

# Evil 4: RUNPATH
gcc -Wl,-rpath,/tmp,--enable-new-dtags /tmp/dummy.c -o /app/corpus/evil/evil4.elf

# Evil 5: Not an ELF
echo "This is not an ELF file" > /app/corpus/evil/evil5.elf

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
