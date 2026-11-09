#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[INFO] 2023-10-01T12:00:01Z - User: U001 performed Action: VIEW on Item: I001. Status: SUCCESS
[INFO] 2023-10-01T12:00:01Z - User: U001 performed Action: VIEW on Item: I001. Status: SUCCESS
[INFO] 2023-10-01T12:05:00Z - User: u001 performed Action: purCHASE on Item: i001. Status: Success
[ERROR] 2023-10-01T12:06:00Z - User: U002 performed Action: VIEW on Item: I002. Status: FAILED
[INFO] 2023-10-01T12:07:00Z - User: U002 performed Action: view on Item: I002. Status: SUCCESS
[INFO] 2023-10-01T12:08:00Z - User: U002 performed Action: CLICK on Item: I003. Status: SUCCESS
[INFO] 2023-10-01T12:09:00Z - User: U002 performed Action: VIEW on Item: I002. Status: SUCCESS
[INFO] 2023-10-01T12:10:00Z - User: U003 performed Action: LOGIN on Item: SYS. Status: SUCCESS
[INFO] 2023-10-01T12:11:00Z - User: U003 performed Action: LOGIN on Item: SYS. Status: SUCCESS
[INFO] 2023-10-01T12:12:00Z - User: U003 performed Action: logout on Item: sys. Status: success
[INFO] 2023-10-01T12:12:00Z - User: U003 performed Action: LOGOUT on Item: SYS. Status: SUCCESS
[WARNING] 2023-10-01T12:13:00Z - User: U004 performed Action: SEARCH on Item: I999. Status: FAILED
EOF

    chmod -R 777 /home/user
