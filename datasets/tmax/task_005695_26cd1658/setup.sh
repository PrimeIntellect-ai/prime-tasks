#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git python3-setuptools
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/billing_service
cd /home/user/billing_service
git init

# Create config.ini
cat << 'EOF' > config.ini
[DEFAULT]
API_SECRET=zk99_fX82_legacy_auth_key
EOF

# Create payload.dat encoded in UTF-16 LE
python3 -c "import json; open('payload.dat', 'wb').write(json.dumps({'customer': 'AcmeCorp', 'amount': 10500}).encode('utf-16-le'))"

# Create proper ingest.py
cat << 'EOF' > ingest.py
import json
import configparser

def main():
    config = configparser.ConfigParser()
    config.read('config.ini')
    secret = config['DEFAULT'].get('API_SECRET', '')

    if not secret:
        print("Error: API_SECRET is missing!")
        return

    with open('payload.dat', 'r', encoding='utf-16-le') as f:
        data = json.load(f)

    report = {
        "status": "success",
        "secret_used": secret,
        "customer": data.get("customer"),
        "amount": data.get("amount")
    }

    with open('/home/user/billing_status.json', 'w') as f:
        json.dump(report, f)

    print("Ingestion successful.")

if __name__ == "__main__":
    main()
EOF

# Create proper setup.py
cat << 'EOF' > setup.py
from setuptools import setup

setup(
    name='billing_service',
    version='1.0',
    install_requires=[
        'requests',
        'urllib3'
    ]
)
EOF

# Create build.sh
cat << 'EOF' > build.sh
#!/bin/bash
python3 setup.py build
EOF
chmod +x build.sh

git add config.ini payload.dat ingest.py setup.py build.sh
git config user.email "oncall@example.com"
git config user.name "OnCall"
git commit -m "Initial working state with correct API key and encodings"

# Introduce the bugs (The hotfix)
# 1. Break config.ini
cat << 'EOF' > config.ini
[DEFAULT]
API_SECRET=
EOF

# 2. Break ingest.py (remove encoding)
cat << 'EOF' > ingest.py
import json
import configparser

def main():
    config = configparser.ConfigParser()
    config.read('config.ini')
    secret = config['DEFAULT'].get('API_SECRET', '')

    if not secret:
        print("Error: API_SECRET is missing!")
        return

    with open('payload.dat', 'r') as f:
        data = json.load(f)

    report = {
        "status": "success",
        "secret_used": secret,
        "customer": data.get("customer"),
        "amount": data.get("amount")
    }

    with open('/home/user/billing_status.json', 'w') as f:
        json.dump(report, f)

    print("Ingestion successful.")

if __name__ == "__main__":
    main()
EOF

# 3. Break setup.py (syntax error missing comma)
cat << 'EOF' > setup.py
from setuptools import setup

setup(
    name='billing_service',
    version='1.0',
    install_requires=[
        'requests'
        'urllib3'
    ]
)
EOF

git add config.ini ingest.py setup.py
git commit -m "Emergency hotfix: Update dependencies and read logic"

chown -R user:user /home/user/billing_service
chmod -R 777 /home/user
