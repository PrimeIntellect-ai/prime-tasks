#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssh-client openssl
pip3 install pytest PyJWT cryptography

useradd -m -s /bin/bash user || true

mkdir -p /home/user/projects/project_alpha/source_code
mkdir -p /home/user/projects/project_beta/source_code
mkdir -p /home/user/projects/project_gamma/source_code

# Generate RSA Key pair for JWT
ssh-keygen -t rsa -b 2048 -m PEM -f /home/user/platform_key.pem -q -N ""
openssl rsa -in /home/user/platform_key.pem -pubout -outform PEM -out /home/user/platform_pub.pem

# Python script to generate JWTs
cat << 'EOF' > /home/user/gen_jwt.py
import jwt
import datetime

with open('/home/user/platform_key.pem', 'rb') as f:
    private_key = f.read()

def create_token(role, expired=False):
    exp = datetime.datetime.utcnow() - datetime.timedelta(days=1) if expired else datetime.datetime.utcnow() + datetime.timedelta(days=1)
    payload = {
        "deploy_role": role,
        "exp": exp
    }
    return jwt.encode(payload, private_key, algorithm="RS256")

# Alpha: Valid
with open('/home/user/projects/project_alpha/deploy_token.jwt', 'w') as f:
    f.write(create_token("platform_admin"))

# Beta: Invalid Role
with open('/home/user/projects/project_beta/deploy_token.jwt', 'w') as f:
    f.write(create_token("developer"))

# Gamma: Valid Token
with open('/home/user/projects/project_gamma/deploy_token.jwt', 'w') as f:
    f.write(create_token("platform_admin"))
EOF

# Generate tokens, then run generation
python3 /home/user/gen_jwt.py
rm /home/user/gen_jwt.py /home/user/platform_key.pem # Remove private key and generator

# Setup Project Alpha (PASS)
cat << 'EOF' > /home/user/projects/project_alpha/source_code/main.py
print("Hello World")
# Safe code
EOF
cat << 'EOF' > /home/user/projects/project_alpha/deploy.sh
#!/bin/bash
echo "Deploying..."
systemctl restart myapp
EOF

# Setup Project Beta (FAIL: invalid_token, hardcoded_secrets)
cat << 'EOF' > /home/user/projects/project_beta/source_code/api.js
const API_KEY = "MOCK_SEC_aB3dE5fG7hI9jK1l"; // Hardcoded secret
console.log("Starting API");
EOF
cat << 'EOF' > /home/user/projects/project_beta/deploy.sh
#!/bin/bash
echo "Deploying beta..."
cp -r * /var/www/html/
EOF

# Setup Project Gamma (FAIL: privilege_escalation_risk)
cat << 'EOF' > /home/user/projects/project_gamma/source_code/config.yml
database: "postgres"
EOF
cat << 'EOF' > /home/user/projects/project_gamma/deploy.sh
#!/bin/bash
chmod 777 /var/www/html/uploads
sudo su -c "systemctl restart nginx"
EOF

chown -R user:user /home/user/projects
chown user:user /home/user/platform_pub.pem

chmod -R 777 /home/user
