#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl gcc tar gawk sed
    pip3 install pytest

    mkdir -p /app /var/www/html /home/user

    # Configure Nginx to listen on 8080
    sed -i 's/listen 80 default_server;/listen 8080 default_server;/g' /etc/nginx/sites-available/default
    sed -i 's/listen \[::\]:80 default_server;/listen \[::\]:8080 default_server;/g' /etc/nginx/sites-available/default

    # Generate Redis population commands
    echo "HSET user_map 105 alice" > /app/redis_data.txt
    echo "HSET user_map 106 bob" >> /app/redis_data.txt
    echo "HSET user_map 107 charlie" >> /app/redis_data.txt
    # Add a few more to simulate a larger dataset
    for i in $(seq 108 200); do
        echo "HSET user_map $i user$i" >> /app/redis_data.txt
    done

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service nginx start
redis-server --daemonize yes
sleep 1
cat /app/redis_data.txt | redis-cli > /dev/null
EOF
    chmod +x /app/start_services.sh

    # Generate mock log files and archives
    mkdir -p /tmp/logs/day1 /tmp/logs/day2
    echo "[1700000000] 105 LOGIN" > /tmp/logs/day1/log1.log
    echo "[1700000005] 106 DOWNLOAD" >> /tmp/logs/day1/log1.log
    echo "[1700000010] 105 UPLOAD" > /tmp/logs/day2/log2.log
    echo "[1700000015] 107 LOGOUT" >> /tmp/logs/day2/log2.log
    echo "[1700000020] 999 UNKNOWN_ACTION" >> /tmp/logs/day2/log2.log

    cd /tmp/logs
    tar -czf day1.tar.gz day1
    tar -czf day2.tar.gz day2
    tar -cf /var/www/html/backup_pool.tar day1.tar.gz day2.tar.gz

    # Cleanup temp logs
    rm -rf /tmp/logs

    # Setup user and permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
