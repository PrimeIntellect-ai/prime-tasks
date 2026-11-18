#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
content = b"""ID,Name,Email,Comments
1,Alice,alice@example.com,Good customer
2,Bob,bob@example.com,"Needs a callback\nurgently"
3,Charlie,charlie@example.com,Standard tier
4,Alice Two,ALICE@example.com,Duplicate email
5,Dave,dave@example.com,Normal row
6,Eve,eve@example.com,"Carriage return\rhere"
7,Frank,frank@example.com,Another good customer
"""
with open("/home/user/input.csv", "wb") as f:
    f.write(content)
'

    chmod -R 777 /home/user
