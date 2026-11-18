#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git make
    pip3 install pytest

    mkdir -p /app/fin_calc-1.2.0
    cd /app/fin_calc-1.2.0
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > app.py
from flask import Flask, request, jsonify
from decimal import Decimal

app = Flask(__name__)

@app.route('/variance', methods=['POST'])
def variance():
    if request.headers.get('X-Auth-Token') != 'super-secret-token-99':
        return jsonify({"error": "unauthorized"}), 401

    data = request.json.get('data', [])
    try:
        # Correct decimal logic
        dec_data = [Decimal(str(x)) for x in data]
        mean = sum(dec_data) / Decimal(len(dec_data))
        var = sum((x - mean) ** Decimal('2') for x in dec_data) / Decimal(len(dec_data))
        return jsonify({"variance": str(var)})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > requirements.txt
Flask==2.2.5
Werkzeug==2.2.3
EOF

    cat << 'EOF' > Makefile
install:
	pip install -r requirements.txt
EOF

    git add app.py requirements.txt Makefile
    git commit -m "Initial commit"

    # Create 150 dummy commits
    for i in $(seq 1 150); do
        echo "# dummy $i" >> app.py
        git commit -am "Dummy commit $i"
    done

    # Introduce the floating point bug (Bad state)
    sed -i 's/dec_data = \[Decimal(str(x)) for x in data\]/dec_data = [float(x) for x in data]/' app.py
    sed -i "s/Decimal('2')/2/g" app.py
    sed -i "s/Decimal(len(dec_data))/len(dec_data)/g" app.py
    git commit -am "Optimize variance calculation with native floats"

    # Create 47 more dummy commits
    for i in $(seq 151 197); do
        echo "# dummy $i" >> app.py
        git commit -am "Dummy commit $i"
    done

    # Introduce the Makefile bug
    sed -i 's/pip install -r requirements.txt/pip install Flaskkkkkk -r requirements.txt/' Makefile
    git commit -am "Update Makefile dependencies"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
