#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl openssh-client curl
pip3 install pytest

mkdir -p /home/user/server/cgi-bin
mkdir -p /home/user/server/certs
mkdir -p /home/user/server/hidden

# 1. Create CA and generate a signed client cert and SSH key for the bundle
openssl req -x509 -newkey rsa:2048 -keyout /home/user/server/ca.key -out /home/user/server/ca.crt -days 365 -nodes -subj "/CN=Internal-CA"
ssh-keygen -t rsa -b 2048 -f /home/user/server/hidden/ssh_key -N "" -q
openssl req -newkey rsa:2048 -keyout /home/user/server/hidden/client.key -out /home/user/server/hidden/client.csr -nodes -subj "/CN=admin-sec-ops"
openssl x509 -req -in /home/user/server/hidden/client.csr -CA /home/user/server/ca.crt -CAkey /home/user/server/ca.key -CAcreateserial -out /home/user/server/hidden/client.crt -days 365

# Create the bundle
cat /home/user/server/hidden/client.crt /home/user/server/hidden/ssh_key > /home/user/server/hidden/cert_bundle.pem

# 2. Create the vulnerable CGI script
cat << 'EOF' > /home/user/server/cgi-bin/check_cert.sh
#!/bin/bash
echo "Content-type: text/plain"
echo ""

cert=$(echo "$QUERY_STRING" | sed -n 's/.*cert=\([^&]*\).*/\1/p')

if [[ -z "$cert" ]]; then
    echo "Error: Missing cert parameter"
    exit 0
fi

if [[ "$cert" == *" "* ]]; then
    echo "Error: Spaces are not allowed in the cert name"
    exit 0
fi

eval "openssl verify -CAfile /home/user/server/ca.crt /home/user/server/certs/${cert}.crt" 2>&1
EOF
chmod +x /home/user/server/cgi-bin/check_cert.sh

useradd -m -s /bin/bash user || true

# Start the CGI server in the background when a shell is opened
echo 'cd /home/user/server && python3 -m http.server --cgi 8080 >/dev/null 2>&1 &' >> /home/user/.bashrc
echo 'sleep 2' >> /home/user/.bashrc

chmod -R 777 /home/user
