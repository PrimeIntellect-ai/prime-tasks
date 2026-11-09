#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pandas numpy gTTS polars duckdb SpeechRecognition pydub

    mkdir -p /home/user/data
    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os
from gtts import gTTS

# Generate CSV
os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

n_rows = 1_000_000
user_ids = np.random.randint(8000, 8100, n_rows)
regions = np.random.choice(["NA-East", "NA-West", "EU-Central", "APAC"], n_rows)
amounts = np.random.uniform(10.0, 500.0, n_rows)

texts = []
for uid, reg in zip(user_ids, regions):
    if uid == 8094 and reg == "NA-East":
        texts.append("Urgent! Please process this urgent request ASAP.")
    else:
        texts.append("Standard interaction log entry.")

df = pd.DataFrame({
    'user_id': user_ids,
    'region_code': regions,
    'transaction_amount': amounts,
    'interaction_text': texts
})

target_mask = (df['user_id'] == 8094) & (df['region_code'] == 'NA-East')
num_targets = target_mask.sum()
df.loc[target_mask, 'transaction_amount'] = 45210.50 / num_targets

df.to_csv('/home/user/data/interactions.csv', index=False)

# Generate Audio
tts = gTTS("Please filter the dataset where the user ID is 8094 and the region code is NA-East.")
tts.save("/app/query.mp3")
os.system("ffmpeg -i /app/query.mp3 -y /app/query.wav")
os.remove("/app/query.mp3")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
