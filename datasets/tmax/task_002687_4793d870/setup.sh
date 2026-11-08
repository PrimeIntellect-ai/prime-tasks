#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget xz-utils build-essential pkg-config libgnutls28-dev
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget https://marlam.de/msmtp/releases/msmtp-1.8.24.tar.xz
    tar -xf msmtp-1.8.24.tar.xz
    rm msmtp-1.8.24.tar.xz

    # Apply the perturbation
    sed -i 's/^install:/nstall:/' /app/msmtp-1.8.24/Makefile.in

    # Create the oracle script
    cat << 'EOF' > /app/oracle_router.sh
#!/bin/bash
file="$1"

list_id=$(grep -i '^List-Id:' "$file" 2>/dev/null)
subject=$(grep -i '^Subject:' "$file" 2>/dev/null)

if echo "$list_id" | grep -qi 'dev\.local'; then
    echo "ROUTE_TO: 8081"
elif echo "$list_id" | grep -qi 'announce\.local'; then
    echo "ROUTE_TO: 8082"
elif [ -z "$list_id" ] && echo "$subject" | grep -qi '\[URGENT\]'; then
    echo "ROUTE_TO: 8089"
else
    echo "ROUTE_TO: 8080"
fi
EOF
    chmod +x /app/oracle_router.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
