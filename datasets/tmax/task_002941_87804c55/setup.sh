#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl cargo
    pip3 install pytest flask

    # Create Flask app
    cat << 'EOF' > /opt/flask_app.py
from flask import Flask, request
import os

app = Flask(__name__)
os.makedirs('/tmp/flask_uploads', exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return 'No file part', 400
    file = request.files['file']
    if file.filename == '':
        return 'No selected file', 400
    file.save(os.path.join('/tmp/flask_uploads', file.filename))
    return 'Success', 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create start script
    cat << 'EOF' > /start_services.sh
#!/bin/bash
if ! pgrep -x redis-server > /dev/null; then
    redis-server --daemonize yes
fi
if ! pgrep -f "python3 /opt/flask_app.py" > /dev/null; then
    nohup python3 /opt/flask_app.py > /tmp/flask.log 2>&1 &
    sleep 1
fi
EOF
    chmod +x /start_services.sh
    echo "/start_services.sh" >> /etc/bash.bashrc

    # Create corpora
    mkdir -p /opt/corpora/clean /opt/corpora/evil
    for i in $(seq 1 10); do
        num=$(printf "%02d" $i)

        # Clean corpus
        cdir="/opt/corpora/clean/clean_$num"
        mkdir -p "$cdir"
        echo "clean data $i" > "$cdir/file.txt"
        ln -s file.txt "$cdir/symlink.txt"

        # Evil corpus
        edir="/opt/corpora/evil/evil_$num"
        mkdir -p "$edir"

        rem=$((i % 3))
        if [ "$rem" -eq 0 ]; then
            ln -s /etc/passwd "$edir/passwd"
        elif [ "$rem" -eq 1 ]; then
            ln -s ../../../../../../../../../../etc "$edir/breakout"
        else
            ln -s loop2 "$edir/loop1"
            ln -s loop1 "$edir/loop2"
        fi
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
