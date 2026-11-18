#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

mkdir -p /home/user/legacy_project

cat << 'EOF' > /home/user/legacy_project/requirements.txt
Flask==0.10.1
Werkzeug==0.9.4
EOF

cat << 'EOF' > /home/user/legacy_project/app.py
import urllib2
from flask import Flask, request

app = Flask(__name__)

@app.route('/evaluate', methods=['GET'])
def evaluate():
    try:
        expr = request.args.get('expr')
        if not expr:
            return "ERROR", 400

        # Build local variables dictionary
        locals_dict = {}
        for key, value in request.args.items():
            if key != 'expr':
                locals_dict[key] = int(value)

        # DANGEROUS: Using eval directly in Python 2
        result = eval(expr, {"__builtins__": None}, locals_dict)
        return str(result)
    except Exception, e:
        print "Error occurred: ", e
        return "ERROR", 400

if __name__ == '__main__':
    app.run(port=8080)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
