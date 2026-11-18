#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest numpy pandas scikit-learn redis python-dotenv

    mkdir -p /app/services/emitter
    mkdir -p /app/services/worker
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/services/emitter/.env
REDIS_HOST=localhost
REDIS_PORT=6380
EOF

    cat << 'EOF' > /app/services/start.sh
#!/bin/bash
redis-server --daemonize yes
sleep 1
export PYTHONPATH=/home/user
python3 /app/services/emitter/emitter.py &
python3 /app/services/worker/worker.py &
wait
EOF
    chmod +x /app/services/start.sh

    cat << 'EOF' > /app/services/emitter/emitter.py
import os
import time
import redis
import numpy as np
from dotenv import load_dotenv

load_dotenv('/app/services/emitter/.env')
r = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=int(os.getenv('REDIS_PORT', 6379)))

while True:
    try:
        r.ping()
        if np.random.rand() > 0.5:
            mat = np.random.uniform(0.1, 1.0, (10, 10))
        else:
            base = np.random.rand(10)
            mat = np.tile(base, (10, 1)) + np.random.normal(0, 1e-8, (10, 10))

        csv_data = "\n".join([",".join(map(str, row)) for row in mat])
        r.lpush('spectra_queue', csv_data)
        time.sleep(1)
    except Exception as e:
        print("Emitter error:", e)
        time.sleep(2)
EOF

    cat << 'EOF' > /app/services/worker/worker.py
import os
import time
import redis
import numpy as np
from sklearn.decomposition import NMF

r = redis.Redis(host='localhost', port=6379)

while True:
    try:
        item = r.brpop('spectra_queue', timeout=5)
        if item:
            csv_data = item[1].decode('utf-8')
            temp_csv_path = '/app/services/worker/temp.csv'
            with open(temp_csv_path, 'w') as f:
                f.write(csv_data)

            rows = csv_data.strip().split('\n')
            mat = np.array([[float(x) for x in row.split(',')] for row in rows])

            nmf = NMF(n_components=2, init='nndsvd', random_state=0, max_iter=200)
            W = nmf.fit_transform(mat)

            with open('/app/services/worker/success.log', 'a') as f:
                f.write('Success\n')
    except Exception as e:
        print("Worker error:", e)
        if "NMF" in str(e) or isinstance(e, ValueError):
            os._exit(1)
        time.sleep(1)
EOF

    python3 -c "
import numpy as np
import os
for i in range(20):
    mat = np.random.uniform(0.1, 1.0, (10, 10))
    np.savetxt(f'/app/corpus/clean/clean_{i}.csv', mat, delimiter=',')
for i in range(20):
    base = np.random.rand(10)
    mat = np.tile(base, (10, 1)) + np.random.normal(0, 1e-8, (10, 10))
    np.savetxt(f'/app/corpus/evil/evil_{i}.csv', mat, delimiter=',')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
