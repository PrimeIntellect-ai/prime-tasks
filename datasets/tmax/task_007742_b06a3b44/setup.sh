#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
os.makedirs("/home/user/raw_data", exist_ok=True)
tsv_content = """greeting\tes\tHola
farewell\tes\tAdiós
apple\tes\tManzana
zebra\tes\tCebra
greeting\tzh\t你好
farewell\tzh\t再见
apple\tzh\t苹果
zebra\tzh\t斑马
greeting\tar\tمرحبًا
farewell\tar\tوداعا
apple\tar\tتفاحة
zebra\tar\tحمار وحشي
"""
with open("/home/user/raw_data/translations.tsv", "w", encoding="utf-8") as f:
    f.write(tsv_content)
'

    chmod -R 777 /home/user
