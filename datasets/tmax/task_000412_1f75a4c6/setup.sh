#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libtbb-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    python3 -c '
with open("/home/user/data/chunk_A.csv", "wb") as f:
    f.write(b"event_id,timestamp,user_name,action\n")
    f.write(b"E105,2023-10-01T10:05:00,Alice,logout\n")
    f.write(b"E101,2023-10-01T10:00:00,Jos\xe9,login\n")
    f.write(b"E102,2023-10-01T10:01:00,Bob,click\n")
    f.write(b"E103,2023-10-01T10:02:00,M\xfcller,purchase\n")
'

    python3 -c '
with open("/home/user/data/chunk_B.csv", "wb") as f:
    f.write(b"event_id,timestamp,user_name,action\n")
    f.write(b"E102,2023-10-01T10:01:00,Bob,click\n")
    f.write(b"E104,2023-10-01T10:04:00,Fran\xe7ois,login\n")
    f.write(b"E101,2023-10-01T10:00:00,Jos\xe9,login\n")
    f.write(b"E106,2023-10-01T10:06:00,Charlie,click\n")
'

    python3 -c '
with open("/home/user/data/chunk_C.csv", "wb") as f:
    f.write(b"event_id,timestamp,user_name,action\n")
    f.write(b"E108,2023-10-01T10:10:00,Bj\xf6rn,logout\n")
    f.write(b"E107,2023-10-01T10:08:00,Diana,purchase\n")
    f.write(b"E104,2023-10-01T10:04:00,Fran\xe7ois,login\n")
    f.write(b"E103,2023-10-01T10:02:00,M\xfcller,purchase\n")
'

    chmod -R 777 /home/user
