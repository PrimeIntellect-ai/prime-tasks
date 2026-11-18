#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest gunicorn

    useradd -m -s /bin/bash user || true

    mkdir -p /app/api-server /home/user/run /home/user/data

    cat << 'EOF' > /app/api-server/app.py
def wsgi(environ, start_response):
    start_response('200 OK', [('Content-Type', 'text/plain')])
    return b"Hello World\n"
EOF

    cat << 'EOF' > /app/api-server/gunicorn.conf.py
workers = 1
bind = "unix:/var/run/backend.sock"
EOF

    cat << 'EOF' > /app/slow_analyzer.sh
#!/bin/bash
sum=0
count=0
while read -r line; do
    status=$(echo "$line" | awk '{print $9}')
    if [ "$status" == "502" ]; then
        latency=$(echo "$line" | awk '{print $10}')
        sum=$(echo "$sum + $latency" | bc -l)
        count=$((count+1))
    fi
done < /home/user/data/large_access.log

if [ "$count" -gt 0 ]; then
    printf "%.2f\n" $(echo "$sum / $count" | bc -l)
fi
EOF
    chmod +x /app/slow_analyzer.sh

    python3 -c "
import random
with open('/home/user/data/large_access.log', 'w') as f:
    for i in range(50000):
        status = 502 if random.random() < 0.1 else 200
        latency = random.uniform(10.0, 100.0)
        f.write(f'192.168.1.1 - - [10/Oct/2023:13:55:36 -0700] \"GET /api HTTP/1.1\" {status} {latency:.2f}\n')
"

    chown -R user:user /home/user/run /home/user/data
    chmod -R 777 /home/user
