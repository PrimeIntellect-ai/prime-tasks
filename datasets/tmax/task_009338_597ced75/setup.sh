#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential openssl ca-certificates rustc cargo jq
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/repo/src /home/user/repo/certs /home/user/policy-scanner

    # Create auth.js
    cat << 'EOF' > /home/user/repo/src/auth.js
app.post('/login', (req, res) => {
    let user = authenticate(req.body.user, req.body.pass);
    if (user) {
        // Open redirect vulnerability
        res.redirect(req.query.return_to || '/dashboard');
    }
});
EOF

    # Generate certificates
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /home/user/repo/certs/ca.key -out /home/user/repo/certs/ca.crt -subj "/CN=Internal Dev CA"
    openssl req -nodes -newkey rsa:2048 -keyout /home/user/repo/certs/server.key -out /home/user/repo/certs/server.csr -subj "/CN=staging.local"
    openssl x509 -req -in /home/user/repo/certs/server.csr -CA /home/user/repo/certs/ca.crt -CAkey /home/user/repo/certs/ca.key -CAcreateserial -out /home/user/repo/certs/server.crt -days 365

    # Create deploy.yaml and hash
    cat << 'EOF' > /home/user/repo/deploy.yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-app
EOF

    cd /home/user/repo
    sha256sum deploy.yaml > deploy.yaml.sha256
    echo "  namespace: tampered" >> deploy.yaml

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
