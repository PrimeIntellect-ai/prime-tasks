#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sudo build-essential libsqlite3-dev
pip3 install pytest

useradd -m -s /bin/bash user || true
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

cat << 'EOF' > /home/user/generate_data.py
import csv

with open("/home/user/transactions.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["tx_id", "timestamp", "source_account", "target_account", "amount"])

    # Normal transactions
    writer.writerow([1, 100000, "ACC001", "ACC002", "1000.0"])
    writer.writerow([2, 101000, "ACC001", "ACC003", "1000.0"])

    # Suspicious account 1: ACC123 (over 50k in 24h = 86400s)
    writer.writerow([3, 200000, "ACC123", "ACC005", "20000.0"])
    writer.writerow([4, 250000, "ACC123", "ACC006", "35000.0"]) # 55k total within 50000s

    # Suspicious account 2: ACC456 (over 50k in 24h)
    writer.writerow([5, 300000, "ACC456", "ACC007", "50001.0"])

    # Cycle 1 involving ACC123: ACC123 -> ACC999 -> ACC888 -> ACC123
    writer.writerow([6, 400000, "ACC123", "ACC999", "100.0"])
    writer.writerow([7, 401000, "ACC999", "ACC888", "100.0"])
    writer.writerow([8, 402000, "ACC888", "ACC123", "100.0"])

    # Cycle 2 involving ACC456: ACC456 -> ACC777 -> ACC666 -> ACC456
    writer.writerow([9, 500000, "ACC456", "ACC777", "100.0"])
    writer.writerow([10, 501000, "ACC777", "ACC666", "100.0"])
    writer.writerow([11, 502000, "ACC666", "ACC456", "100.0"])

    # Fake cycle without a suspicious account
    writer.writerow([12, 600000, "ACC111", "ACC222", "100.0"])
    writer.writerow([13, 601000, "ACC222", "ACC333", "100.0"])
    writer.writerow([14, 602000, "ACC333", "ACC111", "100.0"])
EOF

python3 /home/user/generate_data.py
chown user:user /home/user/transactions.csv

chmod -R 777 /home/user
