#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv cron wget tar

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app/tests/corpus/evil /app/tests/corpus/clean

    # Download and vendor pexpect-4.8.0
    cd /app
    wget https://files.pythonhosted.org/packages/source/p/pexpect/pexpect-4.8.0.tar.gz
    tar -xzf pexpect-4.8.0.tar.gz
    rm pexpect-4.8.0.tar.gz

    # Inject perturbation into setup.py
    sed -i '15iimport os\nif os.environ.get("PEXPECT_INSTALL_TOKEN") != "legacy_admin_override":\n    raise Exception("Missing INSTALL_TOKEN")' /app/pexpect-4.8.0/setup.py

    # Create evil corpus
    cat << 'EOF' > /app/tests/corpus/evil/evil_1.json
[
  {"username": "admin; rm -rf /", "home_dir": "/home/admin", "shell": "/bin/bash"},
  {"username": "test", "home_dir": "/home/test/../../etc", "shell": "/bin/bash"},
  {"username": "toolongusername12345678901234567890", "home_dir": "/home/toolong", "shell": "/bin/bash"},
  {"username": "bad_shell", "home_dir": "/home/badshell", "shell": "/bin/zsh"}
]
EOF

    # Create clean corpus
    cat << 'EOF' > /app/tests/corpus/clean/clean_1.json
[
  {"username": "alice", "home_dir": "/home/alice", "shell": "/bin/bash"},
  {"username": "bob-123", "home_dir": "/home/bob-123", "shell": "/usr/bin/zsh"}
]
EOF

    # Create orchestrator script
    cat << 'EOF' > /home/user/orchestrator.py
print("Orchestrator ran successfully")
EOF

    # Create initial sync_cron
    cat << 'EOF' > /home/user/sync_cron
* * * * * python orchestrator.py >> output/sync.log 2>&1
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
