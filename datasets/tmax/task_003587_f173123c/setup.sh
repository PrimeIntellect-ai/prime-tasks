#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml chardet

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import yaml

os.makedirs("/home/user/logs/appA", exist_ok=True)
os.makedirs("/home/user/logs/appB", exist_ok=True)

config = {
    "directories": ["/home/user/logs/appA", "/home/user/logs/appB"],
    "target_format": "json"
}
with open("/home/user/config.yaml", "w") as f:
    yaml.dump(config, f)

csv_data1 = "id,level,message\n1,INFO,System start\n2,WARN,Memory high\n"
with open("/home/user/logs/appA/log1.csv", "wb") as f:
    f.write(csv_data1.encode("utf-16le"))

json_data1 = "[\n  {\n    \"id\": \"1\",\n    \"level\": \"INFO\",\n    \"message\": \"System start\"\n  },\n  {\n    \"id\": \"2\",\n    \"level\": \"WARN\",\n    \"message\": \"Memory high\"\n  }\n]"
with open("/home/user/logs/appB/log2.json", "wb") as f:
    f.write(json_data1.encode("utf-8"))

csv_data2 = "id,level,message\n3,ERROR,Disk failure\n"
with open("/home/user/logs/appA/log3.csv", "wb") as f:
    f.write(csv_data2.encode("iso-8859-1"))

json_data2 = "[\n  {\n    \"id\": \"3\",\n    \"level\": \"ERROR\",\n    \"message\": \"Disk failure\"\n  }\n]"
with open("/home/user/logs/appB/log4.json", "wb") as f:
    f.write(json_data2.encode("utf-8"))

json_data3 = "[\n  {\n    \"id\": \"4\",\n    \"level\": \"DEBUG\",\n    \"message\": \"Ping\"\n  }\n]"
with open("/home/user/logs/appA/log5.json", "wb") as f:
    f.write(json_data3.encode("utf-8"))
'

    chmod -R 777 /home/user
