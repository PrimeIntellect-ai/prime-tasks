#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang unzip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/generate_logs.py
import csv
import zipfile
import os

data = [
    ["EventID", "Date", "Node", "Log_EN", "Log_ZH", "Log_RU"],
    ["1", "2023-10-01", "Alpha", "System start", "系统启动", "Запуск системы"],
    ["2", "2023-10-01", "Beta", "Disk full\nPlease clear space", "", ""],
    ["3", "2023-10-02", "Alpha", "Network timeout", "网络超时", "Тайм-аут сети"],
    ["4", "2023-10-02", "Gamma", "", "未知错误\n重试", ""],
    ["5", "2023-10-03", "Gamma", "Fatal\ncrash", "", ""],
    ["6", "2023-10-03", "Delta", "All good", "一切正常", "Всё хорошо"],
    ["7", "2023-10-04", "Beta", "Warning:\nHigh CPU", "警告:\nCPU高", ""]
]

with open('/home/user/raw_logs.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerows(data)

with zipfile.ZipFile('/home/user/raw_logs.zip', 'w', zipfile.ZIP_DEFLATED) as zipf:
    zipf.write('/home/user/raw_logs.csv', 'raw_logs.csv')

os.remove('/home/user/raw_logs.csv')
EOF

python3 /home/user/generate_logs.py
rm /home/user/generate_logs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
