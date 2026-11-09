#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

data = [
    b"{\"sensor\": \"Alpha\", \"temp\": 20.0, \"hum\": 45.0}\n",
    b"{\"sensor\": \"Beta\", \"temp\": 25.0, \"hum\": null}\n",
    b"{\"sensor\": \"Alpha\", \"temp\": 22.0, \"hum\": 50.0} \xff\n",
    b"{\"sensor\": \"Gamma\", \"temp\": -100.0, \"hum\": 40.0}\n",
    b"{\"sensor\": \"Beta\", \"temp\": 26.0, \"hum\": null}\n",
    b"{\"s\xfeensor\": \"Delta\", \"t\xfeemp\": 10.0}\n",
    b"{\"sensor\": \"Alpha\", \"temp\": 85.0, \"hum\": 60.0}\n",
    b"INVALID JSON LINE\n"
]

with open("/home/user/raw_telemetry.jsonl", "wb") as f:
    for line in data:
        f.write(line)
'

    chmod -R 777 /home/user
