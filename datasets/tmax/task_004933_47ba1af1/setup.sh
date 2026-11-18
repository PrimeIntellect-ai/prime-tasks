#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick
    pip3 install pytest pandas numpy pillow

    # Generate data
    python3 -c "
import os
import pandas as pd
import numpy as np
from PIL import Image

os.makedirs('/app', exist_ok=True)
os.makedirs('/tmp/frames', exist_ok=True)

intensities = []
for i in range(1, 61):
    intensity = int(100 + 50 * np.sin(i / 5.0))
    intensities.append(intensity)
    img = Image.new('L', (100, 100), color=intensity)
    img.save(f'/tmp/frames/frame_{i:03d}.png')

os.system('ffmpeg -y -framerate 1 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/reaction.mp4')

data = []
truth_data = []
for i in range(1, 61):
    sensor_a = 40.0 + i * 0.5
    if i % 7 == 0:
        data.append([i, 'NULL', '0.0', 'dirty'])
    elif i % 11 == 0:
        data.append([i, '', '0.0', 'empty'])

    data.append([i, f' {sensor_a} ', '12.3', 'ok'])

    anomaly = 1 if (intensities[i-1] > 120 and sensor_a > 45.0) else 0
    truth_data.append([i, sensor_a, intensities[i-1], anomaly])

df_sensor = pd.DataFrame(data, columns=['time_sec', 'sensor_a', 'sensor_b', 'notes'])
df_sensor.to_csv('/app/sensor_log.csv', index=False)

df_truth = pd.DataFrame(truth_data, columns=['time_sec', 'sensor_a', 'intensity', 'anomaly_flag'])
df_truth.to_csv('/app/.hidden_truth.csv', index=False)
"

    # Clean up tmp
    rm -rf /tmp/frames

    # Set up user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
