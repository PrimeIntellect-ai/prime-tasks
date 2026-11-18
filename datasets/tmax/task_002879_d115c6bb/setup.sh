#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest gTTS

    mkdir -p /app

    # Generate audio file
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
text = "For the ETL pipeline, first, reshape the daily temperature columns: temp_morning, temp_afternoon, and temp_evening into a long format. Second, mask the operator_name by keeping only the first two letters and replacing the rest of the name with exactly three asterisks, regardless of the original length. Third, output each reading using the exact template: `[record_id] - Operator [masked_name] recorded [value] during [period]`. Finally, schedule the DAG orchestration cron job to run at 4:15 AM on the first day of every month."
tts = gTTS(text)
tts.save("/app/pipeline_specs.wav")
EOF
    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    # Create oracle
    cat << 'EOF' > /app/reference_oracle.py
#!/usr/bin/env python3
import sys
import csv

def process():
    reader = csv.DictReader(sys.stdin)
    for row in reader:
        record_id = row['record_id']
        name = row['operator_name']
        masked_name = name[:2] + "***" if len(name) >= 2 else name + "***"

        for period in ['temp_morning', 'temp_afternoon', 'temp_evening']:
            val = row[period]
            period_name = period.split('_')[1]
            print(f"{record_id} - Operator {masked_name} recorded {val} during {period_name}")

if __name__ == '__main__':
    process()
EOF
    chmod +x /app/reference_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
