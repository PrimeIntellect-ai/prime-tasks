#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server build-essential libhiredis-dev curl
    pip3 install pytest flask redis python-dotenv

    mkdir -p /home/user/app/nginx
    mkdir -p /home/user/app/api
    mkdir -p /home/user/app/worker/logs
    mkdir -p /home/user/app/corpora/clean
    mkdir -p /home/user/app/corpora/evil

    # Nginx config
    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/submit {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    # Flask API app
    cat << 'EOF' > /home/user/app/api/app.py
import os
from flask import Flask, request, jsonify
import redis
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)

redis_host = os.getenv('REDIS_HOST', '127.0.0.1')
redis_port = int(os.getenv('REDIS_PORT', 6379))
r = redis.Redis(host=redis_host, port=redis_port)

@app.route('/api/submit', methods=['POST'])
def submit():
    data = request.json
    code = data.get('code', '')
    r.lpush('submissions', code)
    return jsonify({"status": "queued"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # API .env
    cat << 'EOF' > /home/user/app/api/.env
REDIS_HOST=127.0.0.1
REDIS_PORT=6380
EOF

    # Worker C++ source
    cat << 'EOF' > /home/user/app/worker/worker.cpp
#include <iostream>
#include <hiredis/hiredis.h>
#include <unistd.h>
#include <fstream>
#include <string>

int main() {
    std::string redis_host = "127.0.0.1";
    int redis_port = 6380;

    std::ifstream conf("worker.conf");
    std::string line;
    while(std::getline(conf, line)) {
        if(line.find("REDIS_HOST=") == 0) redis_host = line.substr(11);
        if(line.find("REDIS_PORT=") == 0) redis_port = std::stoi(line.substr(11));
    }

    redisContext *c = redisConnect(redis_host.c_str(), redis_port);
    if (c == NULL || c->err) {
        if (c) {
            std::cerr << "Error: " << c->errstr << std::endl;
            redisFree(c);
        } else {
            std::cerr << "Can't allocate redis context" << std::endl;
        }
        return 1;
    }

    while (true) {
        redisReply *reply = (redisReply *)redisCommand(c, "BRPOP submissions 1");
        if (reply && reply->type == REDIS_REPLY_ARRAY && reply->elements == 2) {
            std::ofstream log("logs/processed.log", std::ios_base::app);
            log << "Processed: " << reply->element[1]->str << std::endl;
        }
        if (reply) freeReplyObject(reply);
    }
    redisFree(c);
    return 0;
}
EOF

    # Worker Makefile (broken)
    cat << 'EOF' > /home/user/app/worker/Makefile
all: worker_daemon

worker_daemon: worker.o
	g++ -o worker_daemon worker.o

worker.o: worker.cpp
	g++ -c worker.cpp

clean:
	rm -f *.o worker_daemon
EOF

    # Worker config
    cat << 'EOF' > /home/user/app/worker/worker.conf
REDIS_HOST=127.0.0.1
REDIS_PORT=6380
EOF

    # Startup script
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx/nginx.conf
cd /home/user/app/api && python3 app.py &
cd /home/user/app/worker && ./worker_daemon &
EOF
    chmod +x /home/user/app/start_services.sh

    # Sanitizer template
    cat << 'EOF' > /home/user/app/sanitizer.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <file>" << std::endl;
        return 1;
    }
    // Implement sanitizer logic here
    return 0;
}
EOF

    # Corpora
    cat << 'EOF' > /home/user/app/corpora/clean/matrix_mult.cpp
#include <vector>
void mult(std::vector<int>& a, std::vector<int>& b) {
    // simple numerical op
}
int main() { return 0; }
EOF

    cat << 'EOF' > /home/user/app/corpora/evil/shellcode.cpp
#include <stdlib.h>
int main() {
    system("rm -rf /");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/corpora/evil/syscall_asm.cpp
int main() {
    __asm__("mov $0x3b, %rax\n"
            "syscall");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
