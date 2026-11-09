#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gtts

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
from gtts import gTTS
import csv

text = "Please filter the transactions to only include records where the transaction status is 'completed' and the customer region is 'North America'."
tts = gTTS(text)
tts.save('/app/data_request.mp3')

with open('/home/user/transactions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['transaction_id', 'product_category', 'amount', 'status', 'region'])
    writer.writerow([1, "Electronics", 10000.00, "completed", "North America"])
    writer.writerow([2, "Electronics", 5420.50, "completed", "North America"])
    writer.writerow([3, "Apparel", 8000.00, "completed", "North America"])
    writer.writerow([4, "Apparel", 390.25, "completed", "North America"])
    writer.writerow([5, "Home", 4500.00, "completed", "North America"])
    writer.writerow([6, "Electronics", 9999.99, "pending", "North America"])
    writer.writerow([7, "Apparel", 1234.56, "completed", "Europe"])
EOF

    python3 /tmp/setup.py

    chmod -R 777 /app
    chmod -R 777 /home/user
