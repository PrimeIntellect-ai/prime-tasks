#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx gcc libhiredis-dev
    pip3 install pytest redis

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /home/user

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/nginx.conf
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 80;
        root /var/www/html;
        location / {
            autoindex on;
        }
    }
}
EOF

    cat << 'EOF' > /app/corpora/clean/clean_1.csv
1630000000,sensor_01,22.5,normal operation
1630000005,sensor_02,23.1,calibration active
1630000010,sensor_01,22.6,normal operation
EOF

    cat << 'EOF' > /app/corpora/evil/evil_1.csv
1630000000,sensor_01,22.5,normal <script>alert(1)</script>
1630000005,sensor_02,23.1,javascript:execute()
1630000010,sensor_01,22.6,UNION SELECT * FROM users
1630000015,sensor_03,45.0,<body onload=alert('XSS')>
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
