#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import csv

raw_data = [
    # timestamp | server_id | raw_log | cpu_limit
    (100, "srv-A", "info: applied hash=[abc123] successfully", "10.0"),
    (110, "srv-A", "retry: applied hash=[abc123] again", ""),      
    (120, "srv-A", "retry: hash=[abc123] checking", "12.0"),       
    (130, "srv-A", "warn: hash=[def456] sync", "12.0"),            
    (150, "srv-A", "info: hash=[def456] sync", "15.0"),            
    (160, "srv-A", "info: hash=[def456] dup", "15.0"),             
    (100, "srv-B", "init hash=[999zzz] ok", "2.0"),                
    (120, "srv-B", "retry hash=[999zzz]", ""),                     
    (140, "srv-B", "retry hash=[999zzz]", "4.0"),                  
    (145, "srv-B", "retry hash=[999zzz]", "4.0"),                  
    (150, "srv-B", "new hash=[111aaa] ok", ""),                    
    (160, "srv-B", "retry hash=[111aaa] ok", "4.0")                
]

with open('/home/user/raw_configs.txt', 'w') as f:
    for row in raw_data:
        f.write(f"{row[0]} | {row[1]} | {row[2]} | {row[3]}\n")

EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
