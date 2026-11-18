#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/billing
cd /home/user/billing

git config --global user.email "admin@example.com"
git config --global user.name "Admin"
git init
cat << 'EOF' > rates.json
{"multiplier": 1.5}
EOF
git add rates.json
git commit -m "Initial commit: Add rates configuration"
git rm rates.json
git commit -m "Cleanup: remove unused rates file"

cat << 'EOF' > transactions.log
2023-11-05T08:00:00,100.00
2023-11-05T09:00:00,200.00
EOF
# Inject a null byte to simulate corruption on the third line
printf "2023-11-05T10:00:00\000,300.00\n" >> transactions.log

cat << 'EOF' > run.sh
#!/bin/bash
export TZ="America/Los_Angles"
python3 /home/user/billing/processor.py
EOF
chmod +x run.sh

cat << 'EOF' > processor.py
import os
import json
import datetime
import zoneinfo

def load_rates():
    with open('/home/user/billing/rates.json', 'r') as f:
        return json.load(f)

def process_line(line, multiplier):
    # Bug: Infinite loop on Exception
    while True:
        try:
            line = line.strip()
            if not line: return 0.0

            # Fail on corruption
            if '\x00' in line:
                raise ValueError("Corrupted line detected")

            parts = line.split(',')
            ts = datetime.datetime.fromisoformat(parts[0])

            # Fails if TZ is invalid
            tz_name = os.environ.get("TZ", "UTC")
            tz = zoneinfo.ZoneInfo(tz_name)
            local_ts = ts.replace(tzinfo=datetime.timezone.utc).astimezone(tz)

            return float(parts[1]) * multiplier
        except Exception as e:
            # Bug: silently continues on error, creating an infinite loop
            continue

def main():
    try:
        rates = load_rates()
        multiplier = rates.get('multiplier', 1.0)
    except Exception:
        # If rates.json is missing, this will trigger the infinite loop logic later or crash. 
        # Actually let's just let it hang inside the loop instead.
        multiplier = 1.0
        # Wait, to make it hang on missing file, let's read it repeatedly.
        pass

    total = 0.0
    with open('/home/user/billing/transactions.log', 'r') as f:
        for line in f:
            # If rates.json doesn't exist, load_rates will fail. Let's force it to hang.
            while True:
                try:
                    rates = load_rates()
                    multiplier = rates.get('multiplier', 1.0)
                    total += process_line(line, multiplier)
                    break
                except Exception:
                    continue # Infinite hang if file is missing!

    with open('/home/user/billing_summary.txt', 'w') as f:
        f.write(f"Total: {total:.2f}\n")

if __name__ == "__main__":
    main()
EOF

chown -R user:user /home/user/billing
chmod -R 777 /home/user
