#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx curl
    pip3 install pytest redis watchdog markdown

    mkdir -p /app
    mkdir -p /home/user/docs_src
    mkdir -p /home/user/www
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service redis-server start
cat << 'NGINX' > /etc/nginx/sites-available/default
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;
    root /home/user/www;
    index index.html;
    server_name _;
    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX
service nginx restart
python3 /app/watcher.py &
python3 /app/builder.py &
wait
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/watcher.py
import time
import redis
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

r = redis.Redis(host='localhost', port=6379, db=0)

class Handler(FileSystemEventHandler):
    def on_modified(self, event):
        if not event.is_directory and event.src_path.endswith('.md'):
            r.lpush('doc_queue', event.src_path)

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.md'):
            r.lpush('doc_queue', event.src_path)

observer = Observer()
observer.schedule(Handler(), path='/home/user/docs_src', recursive=False)
observer.start()

try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    observer.stop()
observer.join()
EOF

    cat << 'EOF' > /app/builder.py
import time
import redis
import os
import markdown

r = redis.Redis(host='localhost', port=6379, db=0)

while True:
    item = r.brpop('doc_queue', timeout=1)
    if item:
        path = item[1].decode('utf-8')
        if os.path.exists(path):
            try:
                with open(path, 'r') as f:
                    text = f.read()
                html = markdown.markdown(text)
                filename = os.path.basename(path).replace('.md', '.html')
                with open(os.path.join('/home/user/www', filename), 'w') as f:
                    f.write(html)
            except Exception as e:
                pass
EOF

    for i in $(seq 1 50); do
        echo "This is clean file $i" > /home/user/corpora/clean/clean_$i.md
    done

    for i in $(seq 1 25); do
        echo "!INCLUDE[/etc/shadow]" > /home/user/corpora/evil/evil_$i.md
    done

    for i in $(seq 26 50); do
        echo -e "---\n{ invalid: json,\n---\nHello" > /home/user/corpora/evil/evil_$i.md
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
