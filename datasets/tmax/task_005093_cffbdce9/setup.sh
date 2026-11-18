#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python-is-python3 git
    pip3 install pytest

    mkdir -p /home/user/data_pipeline
    cd /home/user/data_pipeline
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Initial good version
    cat << 'EOF' > process_data.py
import sys, json, math
def softmax(x):
    m = max(x)
    e = [math.exp(i - m) for i in x]
    s = sum(e)
    return [i / s for i in e]

if __name__ == "__main__":
    try:
        data = json.load(open(sys.argv[1]))
        res = softmax(data)
        print("Success")
        sys.exit(0)
    except Exception as e:
        print("Error", e)
        sys.exit(1)
EOF

    cat << 'EOF' > large_input.json
[10.0, 750.0, 20.0, 5.0, 800.0]
EOF

    git add process_data.py large_input.json
    git commit -m "Initial commit"

    for i in $(seq 1 200); do
        echo "Commit $i" > dummy.txt
        git add dummy.txt

        if [ $i -eq 42 ]; then
            echo '{"api_key": "DATA_CORP_API_99XQ2"}' > config.json
            git add config.json
        fi
        if [ $i -eq 43 ]; then
            echo '{"api_key": "REDACTED"}' > config.json
            git add config.json
        fi

        # Introduce numerical instability
        if [ $i -eq 105 ]; then
            cat << 'EOF' > process_data.py
import sys, json, math
def softmax(x):
    e = [math.exp(i) for i in x]
    s = sum(e)
    return [i / s for i in e]

if __name__ == "__main__":
    try:
        data = json.load(open(sys.argv[1]))
        res = softmax(data)
        print("Success")
        sys.exit(0)
    except Exception as e:
        print("Error", e)
        sys.exit(1)
EOF
            git add process_data.py
        fi

        git commit -m "Update $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
