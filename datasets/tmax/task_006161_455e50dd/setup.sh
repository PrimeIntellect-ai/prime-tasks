#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/simulator

# 1. Create the run_pipeline.sh script
cat << 'EOF' > /home/user/simulator/run_pipeline.sh
#!/bin/bash

echo "Running Parser Check..."
python3 /home/user/simulator/parser.py
echo "Running Simulator..."
python3 /home/user/simulator/simulator.py
EOF
chmod +x /home/user/simulator/run_pipeline.sh

# 2. Create the buggy parser.py
cat << 'EOF' > /home/user/simulator/parser.py
import json

def resolve_alias(node, config_map):
    # BUG: Infinite recursion on cycles
    if node in config_map:
        return resolve_alias(config_map[node], config_map)
    return node

if __name__ == "__main__":
    test_config = {"node_A": "node_B", "node_B": "node_C", "node_C": "node_A", "node_X": "node_Y"}
    # This will crash
    val = resolve_alias("node_A", test_config)
    print(f"Resolved node_A to: {val}")
EOF

# 3. Create the buggy simulator.py
cat << 'EOF' > /home/user/simulator/simulator.py
import threading

# Global state
total_efficiency = 0.0

def calculate_efficiency(x, y, z):
    # BUG: Missing parentheses for (x^2 + y) / z
    return x ** 2 + y / z

def worker(chunk):
    global total_efficiency
    for x, y, z in chunk:
        val = calculate_efficiency(x, y, z)
        # BUG: Race condition
        total_efficiency += val

if __name__ == "__main__":
    # Read data
    data = []
    with open('/home/user/simulator/data.txt', 'r') as f:
        for line in f:
            x, y, z = map(float, line.strip().split(','))
            data.append((x, y, z))

    # Split data into 4 chunks
    chunk_size = len(data) // 4
    chunks = [data[i:i + chunk_size] for i in range(0, len(data), chunk_size)]

    threads = []
    for chunk in chunks:
        t = threading.Thread(target=worker, args=(chunk,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    with open('/home/user/simulator/final_result.txt', 'w') as f:
        f.write(f"{total_efficiency:.2f}\n")
EOF

# 4. Generate data.txt
cat << 'EOF' > /home/user/simulator/generate_data.py
import random
random.seed(42)
with open('/home/user/simulator/data.txt', 'w') as f:
    for _ in range(1000):
        x = random.randint(1, 10)
        y = random.randint(1, 20)
        z = random.randint(1, 5)
        f.write(f"{x},{y},{z}\n")
EOF
python3 /home/user/simulator/generate_data.py
rm /home/user/simulator/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
