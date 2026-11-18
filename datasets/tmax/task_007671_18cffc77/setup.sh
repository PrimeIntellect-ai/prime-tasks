#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git strace
    pip3 install pytest pandas

    mkdir -p /home/user/log_processor
    cd /home/user/log_processor

    git config --global user.email "devops@example.com"
    git config --global user.name "DevOps Engineer"
    git init

    # Create the dummy log file
    cat << 'EOF' > server_logs.csv
timestamp,level,service,message
2023-10-01T10:00:00,INFO,web,Request received
2023-10-01T10:01:00,CRITICAL,auth,Authentication bypassed
2023-10-01T10:02:00,ERROR,db,Connection timeout
2023-10-01T10:03:00,CRITICAL,auth,Multiple failed logins
2023-10-01T10:04:00,CRITICAL,web,Out of memory
EOF

    # Create the initial python script with the secret
    cat << 'EOF' > process.py
import os
import pandas as pd

SECRET_TOKEN = "xtk_99281_devops_secret"

def process_logs():
    # Attempt to read config from a named pipe (this will block in the next commit)
    # with open('/tmp/config_pipe', 'r') as f:
    #     config = f.read()

    df = pd.read_csv('server_logs.csv')

    # BUG: Wrong filter
    filtered_df = df[(df['level'] == 'INFO') & (df['service'] == 'web')]

    filtered_df.to_csv('/home/user/processed_logs.csv', index=False)
    print("Processing complete.")

if __name__ == "__main__":
    process_logs()
EOF

    git add server_logs.csv process.py
    git commit -m "Initial commit with log processor"

    # Second commit: remove secret, add blocking pipe read
    cat << 'EOF' > process.py
import os
import pandas as pd

SECRET_TOKEN = os.environ.get("SECRET_TOKEN")

def process_logs():
    if not SECRET_TOKEN:
        print("Warning: No token provided.")

    # BUG: This will hang indefinitely if the pipe isn't written to
    with open('/tmp/config_pipe', 'r') as f:
        config = f.read()

    df = pd.read_csv('server_logs.csv')

    # BUG: Wrong filter
    filtered_df = df[(df['level'] == 'INFO') & (df['service'] == 'web')]

    filtered_df.to_csv('/home/user/processed_logs.csv', index=False)
    print("Processing complete.")

if __name__ == "__main__":
    process_logs()
EOF

    # Create the named pipe so it hangs instead of throwing FileNotFoundError
    mkfifo /tmp/config_pipe

    git add process.py
    git commit -m "Refactor to use env var for token and read dynamic config"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 777 /tmp/config_pipe
