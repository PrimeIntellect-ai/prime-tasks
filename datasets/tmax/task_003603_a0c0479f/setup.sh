#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pandas fastapi uvicorn flask opencv-python-headless imageio

    mkdir -p /app

    # Create the video
    ffmpeg -f lavfi -i testsrc=duration=4:size=320x240:rate=30 -c:v libx264 /app/experiment.mp4

    # Create data.csv
    cat << 'EOF' > /app/data.csv
id,event_code
1,500
2,
3,502
4,404
5,
EOF

    # Create pipeline.py
    cat << 'EOF' > /app/pipeline.py
import pandas as pd

def process_data():
    df = pd.read_csv('/app/data.csv')
    # Bug: introduces floats like EVT_500.0 and EVT_nan
    df['token'] = "EVT_" + df['event_code'].astype(str)
    return df

if __name__ == "__main__":
    df = process_data()
    print(df.head())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
