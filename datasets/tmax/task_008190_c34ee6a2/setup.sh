#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip socat curl grep procps
pip3 install pytest

mkdir -p /home/user/app
cat << 'EOF' > /home/user/app/server.sh
#!/bin/bash
read -r REQUEST_LINE
while read -r line; do
    line=$(echo "$line" | tr -d '\r')
    if [ -z "$line" ]; then
        break
    fi
    if [[ "${line,,}" == "user-agent: "* ]]; then
        UA="${line#*: }"
    fi
    if [[ "${line,,}" == "cookie: "* ]]; then
        COOKIE="${line#*: }"
    fi
done

# WAF check: Block standard automated tools
if [[ "${UA,,}" == *"curl"* ]] || [[ "${UA,,}" == *"wget"* ]]; then
    echo -e "HTTP/1.1 403 Forbidden\r\n\r\nAutomated tools blocked."
    exit 0
fi

# Extract session token
SESSION_ID=$(echo "$COOKIE" | grep -oP 'session=\K[^;]*' || true)

echo -e "HTTP/1.1 200 OK\r\n\r\n"
# Vulnerable processing step
eval "echo \"Processing session: $SESSION_ID\"" > /dev/null
EOF
chmod +x /home/user/app/server.sh

useradd -m -s /bin/bash user || true

# Ensure the service starts when a shell is opened
echo 'pgrep socat >/dev/null || nohup socat TCP-LISTEN:8080,reuseaddr,fork EXEC:/home/user/app/server.sh > /dev/null 2>&1 &' >> /etc/bash.bashrc
echo 'pgrep socat >/dev/null || nohup socat TCP-LISTEN:8080,reuseaddr,fork EXEC:/home/user/app/server.sh > /dev/null 2>&1 &' >> /home/user/.bashrc

chmod -R 777 /home/user
