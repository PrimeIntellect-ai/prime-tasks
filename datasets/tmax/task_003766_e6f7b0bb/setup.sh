#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang redis-server nginx curl bc
    pip3 install pytest flask redis

    mkdir -p /app/services /app/bin /app/data /tmp/docs_out

    # Create Nginx config
    cat << 'EOF' > /app/services/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            return 200 "OK";
        }
    }
}
EOF

    # Create Flask app
    cat << 'EOF' > /app/services/app.py
from flask import Flask, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/doc/<id>')
def get_doc(id):
    val = r.get(f"doc:{id}")
    if val:
        return jsonify({"timestamp": val.decode('utf-8')})
    return jsonify({"error": "not found"}), 404

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create start script
    cat << 'EOF' > /app/services/start_all.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/services/app.py &
nginx -c /app/services/nginx.conf &
sleep 2
EOF
    chmod +x /app/services/start_all.sh

    # Create Reference Go code
    cat << 'EOF' > /tmp/process_docs_ref.go
package main
import (
    "archive/tar"
    "fmt"
    "io"
    "os"
    "path/filepath"
    "time"
)
func main() {
    if len(os.Args) < 2 {
        fmt.Println("Usage: process_docs <tarball>")
        return
    }
    f, err := os.Open(os.Args[1])
    if err != nil { panic(err) }
    defer f.Close()
    tr := tar.NewReader(f)
    for {
        hdr, err := tr.Next()
        if err == io.EOF { break }
        if err != nil { panic(err) }

        target := filepath.Join("/tmp/docs_out", hdr.Name)
        os.MkdirAll(filepath.Dir(target), 0755)

        if hdr.Typeflag == tar.TypeReg {
            outFile, err := os.Create(target)
            if err != nil { panic(err) }
            io.Copy(outFile, tr)
            outFile.Close()

            time.Sleep(50 * time.Millisecond)
        }
    }
}
EOF

    # Compile reference binary
    go build -o /app/bin/process_docs_ref /tmp/process_docs_ref.go

    # Put skeleton for user
    mkdir -p /home/user
    cp /tmp/process_docs_ref.go /home/user/process_docs.go

    # Generate tarballs using Python
    cat << 'EOF' > /tmp/gen_tars.py
import tarfile
import struct
import os

with tarfile.open('/app/data/docs_upload.tar', 'w') as tar:
    with open('/tmp/valid.md', 'w') as f: f.write('valid')
    tar.add('/tmp/valid.md', arcname='valid.md')

    with open('/tmp/evil.txt', 'w') as f: f.write('evil')
    tar.add('/tmp/evil.txt', arcname='../evil.txt')

    with open('/tmp/history.wal', 'wb') as f:
        f.write(struct.pack('<IIB', 101, 1620000000, 1))
    tar.add('/tmp/history.wal', arcname='history.wal')

with tarfile.open('/app/data/large_docs.tar', 'w') as tar:
    for i in range(200):
        name = f'/tmp/doc_{i}.md'
        with open(name, 'w') as f: f.write(f'doc {i}')
        tar.add(name, arcname=f'doc_{i}.md')
EOF
    python3 /tmp/gen_tars.py

    # Create verify script
    cat << 'EOF' > /app/verify.sh
#!/bin/bash
res=$(curl -s http://127.0.0.1:8080/api/doc/101)
if ! echo "$res" | grep -q "1620000000"; then
    echo "API check failed"
    exit 1
fi

if [ -f /tmp/evil.txt ]; then
    echo "Zip slip failed"
    exit 1
fi

start_ref=$(date +%s.%N)
/app/bin/process_docs_ref /app/data/large_docs.tar >/dev/null 2>&1
end_ref=$(date +%s.%N)

start_agent=$(date +%s.%N)
/home/user/process_docs /app/data/large_docs.tar >/dev/null 2>&1
end_agent=$(date +%s.%N)

time_ref=$(echo "$end_ref - $start_ref" | bc)
time_agent=$(echo "$end_agent - $start_agent" | bc)

ratio=$(echo "$time_ref / $time_agent" | bc -l)
if (( $(echo "$ratio < 3.0" | bc -l) )); then
    echo "Speedup $ratio < 3.0"
    exit 1
fi
echo "Success"
exit 0
EOF
    chmod +x /app/verify.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
