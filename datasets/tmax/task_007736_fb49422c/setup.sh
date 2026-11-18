#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user/tickets_raw', exist_ok=True)

tickets = [
    {
        "filename": "ticket_1.txt",
        "encoding": "utf-8",
        "content": "Date: 2023-10-01\nEmail: alice@example.com\nError: [ERR_404]\nMessage: The requested file was not found."
    },
    {
        "filename": "ticket_2.txt",
        "encoding": "iso-8859-1",
        "content": "Reported: 2023-10-02\nUser: bob@test.org\nError: []\nMessage: Connection timeout while trying to reach the database. El servidor falló."
    },
    {
        "filename": "ticket_3.txt",
        "encoding": "windows-1252",
        "content": "Date: 2023-10-03\nEmail: charlie@domain.net\nError: []\nMessage: Access denied for user. La sesión expiró con el símbolo €."
    },
    {
        "filename": "ticket_4.txt",
        "encoding": "utf-8",
        "content": "Date: 2023-10-04\nEmail: dave@example.com\nMessage: The application threw an unhandled exception during startup."
    },
    {
        "filename": "ticket_5.txt",
        "encoding": "utf-8",
        "content": "Reported: 2023-10-05\nUser: eve@hacker.net\nError: []\nMessage: Just a generic complaint about the UI. Nothing specific."
    }
]

for t in tickets:
    with open(f"/home/user/tickets_raw/{t['filename']}", 'w', encoding=t['encoding']) as f:
        f.write(t['content'])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
