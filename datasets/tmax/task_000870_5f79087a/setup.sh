#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils gcc
    pip3 install pytest flask requests pyelftools

    mkdir -p /app

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/elf_server.py > /dev/null 2>&1 &
python3 /app/log_server.py > /dev/null 2>&1 &
sleep 2
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/elf_server.py
import flask, base64, subprocess, os
app = flask.Flask(__name__)

@app.route('/fetch')
def fetch():
    idx = flask.request.args.get('id', '1')
    email = f"target_{idx}@example.com"
    c_code = f"""
    #include <stdio.h>
    const char* email = "{email}";
    const char* other = "safe_string_here";
    int main() {{
        printf("%s\\n", email);
        return 0;
    }}
    """
    c_file = f"/tmp/temp_{idx}.c"
    elf_file = f"/tmp/temp_{idx}.elf"
    with open(c_file, "w") as f:
        f.write(c_code)
    subprocess.run(["gcc", c_file, "-o", elf_file], check=True)
    with open(elf_file, "rb") as f:
        elf_data = f.read()
    payload = base64.b64encode(elf_data).decode()
    return flask.jsonify({"id": idx, "payload": payload})

if __name__ == '__main__':
    app.run(port=8001)
EOF

    cat << 'EOF' > /app/log_server.py
import flask
app = flask.Flask(__name__)
logs = []

@app.route('/log', methods=['POST'])
def log_event():
    logs.append(flask.request.json)
    return "OK"

@app.route('/get_logs')
def get_logs():
    return flask.jsonify(logs)

if __name__ == '__main__':
    app.run(port=8002)
EOF

    cat << 'EOF' > /app/verify.py
import requests, base64, subprocess, hmac, hashlib, time, json, os

def verify():
    score = 0.0
    valid_elf_count = 0
    correctly_redacted_count = 0
    correct_log_count = 0
    total = 20

    for i in range(1, total + 1):
        idx = str(i)
        user_email = f"user_{idx}@test.com"
        target_email = f"target_{idx}@example.com"

        try:
            resp = requests.get(f"http://localhost:8000/download?id={idx}&user={user_email}", timeout=5)
            if resp.status_code == 200:
                data = resp.json()
                payload = base64.b64decode(data['payload'])

                elf_path = f"/tmp/verify_{idx}.elf"
                with open(elf_path, "wb") as f:
                    f.write(payload)

                # Check valid ELF
                res = subprocess.run(["readelf", "-S", elf_path], capture_output=True)
                if res.returncode == 0:
                    valid_elf_count += 1

                # Check redaction
                rodata_dump = subprocess.run(["readelf", "-p", ".rodata", elf_path], capture_output=True, text=True)
                dump_out = rodata_dump.stdout

                if target_email not in dump_out and ("*" * len(target_email)) in dump_out and "safe_string_here" in dump_out:
                    correctly_redacted_count += 1

        except Exception:
            pass

    try:
        logs_resp = requests.get("http://localhost:8002/get_logs", timeout=5)
        logs = logs_resp.json()
        log_dict = {log.get('id'): log.get('user_hash') for log in logs if 'id' in log}

        for i in range(1, total + 1):
            idx = str(i)
            user_email = f"user_{idx}@test.com"
            expected_hash = hmac.new(b"AUDIT_KEY", user_email.encode(), hashlib.sha256).hexdigest()
            if log_dict.get(idx) == expected_hash:
                correct_log_count += 1
    except Exception:
        pass

    final_score = (valid_elf_count / total) * 0.4 + (correctly_redacted_count / total) * 0.4 + (correct_log_count / total) * 0.2
    print(final_score)

if __name__ == '__main__':
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
