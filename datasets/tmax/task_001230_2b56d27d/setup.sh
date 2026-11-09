#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_dataset.py
import pandas as pd

data = {
    "ticket_id": [101, 102, 103, 104, 105, 106, 107, 108],
    "text": [
        "The server is down and I cannot connect to the database.",
        "Password reset is not working! Please help me reset my password.",
        "Cannot connect to the wifi network. The server seems offline.",
        "How do I reset my account password? I forgot it.",
        "The database is extremely slow today, queries timeout.",
        "Forgot my password again, please send the reset link.",
        "Server connection refused. Database network issue.",
        "What is the wifi password for the guest network?"
    ]
}

df = pd.DataFrame(data)
df.to_csv("/home/user/tickets.csv", index=False)
EOF
    python3 /tmp/setup_dataset.py

    chmod -R 777 /home/user
