#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest fastapi redis pandas scikit-learn matplotlib requests pydantic numpy

    mkdir -p /app

    cat << 'EOF' > /app/api.py
from fastapi import FastAPI
from pydantic import BaseModel
import redis
import json

app = FastAPI()
r = redis.Redis(host='localhost', port=6379)

class SensorData(BaseModel):
    features: list[float]

@app.post("/ingest")
def ingest(data: SensorData):
    r.rpush('sensor_stream', json.dumps(data.features))
    return {"status": "ok"}
EOF

    cat << 'EOF' > /app/worker.py
import redis
import json
import os
import time
import pandas as pd
import matplotlib.pyplot as plt

# Misconfigured REDIS_PORT
redis_port = int(os.environ.get("REDIS_PORT", 6378))
r = redis.Redis(host='localhost', port=redis_port)

def process_batch():
    data = []
    while True:
        item = r.lpop('sensor_stream')
        if item is None:
            break
        data.append(json.loads(item))

    if not data:
        return

    df = pd.DataFrame(data)
    # Naive dimensionality reduction
    reduced = df.iloc[:, :2]
    reduced.columns = ['pc1', 'pc2']
    reduced.to_csv('/home/user/reduced_data.csv', index=False)

    plt.scatter(reduced['pc1'], reduced['pc2'])
    plt.show() # This clears the figure, causing the saved plot to be blank
    plt.savefig('/home/user/cluster_plot.png')

if __name__ == "__main__":
    while True:
        try:
            process_batch()
        except Exception:
            pass
        time.sleep(1)
EOF

    useradd -m -s /bin/bash user || true

    # Generate raw_sensors.csv
    python3 -c "
import numpy as np
import pandas as pd
np.random.seed(42)
X = np.random.randn(10000, 50)
df = pd.DataFrame(X)
df.to_csv('/home/user/raw_sensors.csv', index=False)
"

    chmod -R 777 /home/user
    chmod -R 777 /app
