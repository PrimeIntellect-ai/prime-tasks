#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import base64

os.makedirs("/home/user/build_env", exist_ok=True)

# manifest.json
with open("/home/user/build_env/manifest.json", "w") as f:
    f.write("{\"files\": [\"config.json\", \"main.py\", \"data file.csv\"]}\n")

# process_asset.sh (buggy)
with open("/home/user/build_env/process_asset.sh", "w") as f:
    f.write("""#!/bin/bash
FILE=$1
echo "Processing $FILE"
# The bug: unquoted FILE causes wc to fail on spaces
wc -c $FILE > /dev/null
""")
os.chmod("/home/user/build_env/process_asset.sh", 0o755)

# build.log
with open("/home/user/build_env/build.log", "w") as f:
    f.write("""[2023-11-14T22:13:20] INFO: Fetching config.json
[2023-11-14T22:13:21] INFO: Fetching main.py
[2023-11-14T22:13:25] INFO: Fetching data file.csv
[2023-11-14T22:13:25] ERROR: Process failed for data file.csv
""")

# server.log
with open("/home/user/build_env/server.log", "w") as f:
    f.write("""1700000000 - GET /config.json 200
1700000001 - GET /main.py 200
1700000005 - GET /data%20file.csv 200
""")

# build_traffic.pcap
pcap_b64 = b"""
1MOyoQIABAAAAAAAAAAAAAAABAAAAAAABgAAAAAAAAABAAAAEAAAAHhXJGUuAAAAXgAAAAAA
AAAAAAAARVQAFAAAAEAGAAABoW1AAMCoAAHAqAABIAAEPAAAACRQAAAAAABHRVQgL2NvbmZp
Zy5qc29uIEhUVFAvMS4xDQpIb3N0OiBsb2NhbGhvc3QNCg0KeFckZTQAAABeAAAAAAAAAAAA
AABFVAAUAAAAQAYAAAGhbUAAwKgAAcCoAAEgAAQ8AAAAJFAAAAAAAEdFVCAvbWFpbi5weSBI
VFRQLzEuMQ0KSG9zdDogbG9jYWxob3N0DQoNCnhXJGVEAAAAXgAAAAAAAAAAAAAARVQAFAAA
AEAGAAABoW1AAMCoAAHAqAABIAAEPAAAACRQAAAAAABHRVQgL2RhdGElMjBmaWxlLmNzdiBI
VFRQLzEuMQ0KSG9zdDogbG9jYWxob3N0DQoNCg==
"""
with open("/home/user/build_env/build_traffic.pcap", "wb") as f:
    f.write(base64.b64decode(pcap_b64))
'

    chmod -R 777 /home/user
