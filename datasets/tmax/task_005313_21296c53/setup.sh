#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg nodejs npm
    pip3 install pytest flask pymongo networkx pandas

    # Install MongoDB
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update && apt-get install -y mongodb-org

    mkdir -p /app
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
mkdir -p /data/db
mongod --fork --logpath /var/log/mongodb.log --dbpath /data/db
# Mock API
cat << 'APP' > /app/api.py
from flask import Flask
app = Flask(__name__)
@app.route('/health')
def health(): return "OK"
if __name__ == '__main__': app.run(port=5000)
APP
python3 /app/api.py &
EOF
    chmod +x /app/start_services.sh

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Clean 1: No cycles
    cat << 'EOF' > /home/user/corpora/clean/graph1.csv
source_account,target_account,timestamp,amount
A,B,2023-01-01,60000
B,C,2023-01-02,60000
C,D,2023-01-03,60000
EOF

    # Clean 2: Cycle but amounts too low
    cat << 'EOF' > /home/user/corpora/clean/graph2.csv
source_account,target_account,timestamp,amount
X,Y,2023-01-01,20000
Y,Z,2023-01-02,60000
Z,X,2023-01-03,60000
EOF

    # Evil 1: 3-node cycle > 50000
    cat << 'EOF' > /home/user/corpora/evil/graph1.csv
source_account,target_account,timestamp,amount
P,Q,2023-01-01,55000
Q,R,2023-01-02,60000
R,P,2023-01-03,50000
EOF

    # Evil 2: 4-node cycle > 50000 alongside noise
    cat << 'EOF' > /home/user/corpora/evil/graph2.csv
source_account,target_account,timestamp,amount
M,N,2023-01-01,10000
I,J,2023-01-01,70000
J,K,2023-01-02,80000
K,L,2023-01-03,75000
L,I,2023-01-04,90000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
