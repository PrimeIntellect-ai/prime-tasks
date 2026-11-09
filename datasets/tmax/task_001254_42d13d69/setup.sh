#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis

    # Create directories
    mkdir -p /home/user/app/nginx
    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil

    # Create Flask app
    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/api/upload', methods=['POST'])
def upload():
    r.incr('uploads_count')
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Create broken Nginx config
    cat << 'EOF' > /home/user/app/nginx/nginx.conf
worker_processes 1;
pid /home/user/app/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/app/nginx/access.log;
    error_log /home/user/app/nginx/error.log;
    server {
        listen 8080;
        # The agent needs to add the /api/ location block here
    }
}
EOF

    # Create start script
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx/nginx.conf
python3 /home/user/app/app.py &
EOF
    chmod +x /home/user/app/start_services.sh

    # Create Clean CSVs
    cat << 'EOF' > /home/user/data/clean/data1.csv
id,val1,val2,experiment_id
1,a,b,12
2,c,d,-3
3,e,f,0
EOF

    cat << 'EOF' > /home/user/data/clean/data2.csv
id,val1,val2,experiment_id
1,x,y,42
2,z,w,99
EOF

    # Create Evil CSVs
    cat << 'EOF' > /home/user/data/evil/data1.csv
id,val1,val2,experiment_id
1,a,b,12.0
2,c,d,-3
3,e,f,0
EOF

    cat << 'EOF' > /home/user/data/evil/data2.csv
id,val1,val2,experiment_id
1,x,y,42
2,z,w,NaN
EOF

    cat << 'EOF' > /home/user/data/evil/data3.csv
id,val1,val2,experiment_id
1,x,y,42
2,z,w,
EOF

    cat << 'EOF' > /home/user/data/evil/data4.csv
id,val1,val2,experiment_id
1,x,y,42
2,z,w,null
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
