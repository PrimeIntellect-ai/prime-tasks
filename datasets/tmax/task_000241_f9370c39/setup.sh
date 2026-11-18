#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    cat << 'EOF' > /home/user/logs/processor_crash.log
thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value: Utf8Error { valid_up_to: 45, error_len: Some(1) }'. Hex dump of payload context: 7b 22 6d 65 73 73 61 67 65 22 3a 20 22 5c 75 64 38 30 30 22 7d (which translates to {"message": "\ud800"})
EOF

    cat << 'EOF' > /home/user/router_config.json
{"downstream_url": "http://127.0.0.1:8081"}
EOF

    for i in $(seq 1 50); do
        echo '{"timestamp": "2023-10-01T12:00:00Z", "message": "Normal log message"}' > /home/user/corpus/clean/log_$i.json
        echo '{"timestamp": "2023-10-01T12:00:01Z", "message": "Evil log message \ud800"}' > /home/user/corpus/evil/log_$i.json
    done

    cat << 'EOF' > /opt/router.py
import http.server, json, urllib.request

class Router(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try:
            with open('/home/user/router_config.json') as f:
                config = json.load(f)
            req = urllib.request.Request(config['downstream_url'], data=post_data, method='POST')
            with urllib.request.urlopen(req) as response:
                self.send_response(response.status)
                self.end_headers()
                self.wfile.write(response.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_response(500)
            self.end_headers()

http.server.HTTPServer(('127.0.0.1', 8080), Router).serve_forever()
EOF

    cat << 'EOF' > /opt/processor.py
import http.server, json, redis, sys

r = redis.Redis(host='127.0.0.1', port=6379, db=0)

class Processor(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try:
            text = post_data.decode('utf-8', errors='strict')
            if r'\ud800' in text or '\\ud800' in text:
                sys.exit(1) # Simulate crash on unpaired surrogate
            data = json.loads(text)
            r.lpush('logs', json.dumps(data))
            self.send_response(200)
            self.end_headers()
        except UnicodeDecodeError:
            sys.exit(1)
        except Exception:
            self.send_response(400)
            self.end_headers()

http.server.HTTPServer(('127.0.0.1', 8081), Processor).serve_forever()
EOF

    chmod -R 777 /home/user
