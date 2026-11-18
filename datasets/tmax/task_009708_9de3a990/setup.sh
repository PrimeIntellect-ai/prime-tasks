#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/data.jsonl
{"id": "A1", "value": 8}
{"id": "B2", "value": 27.0}
{"id": "C3", "value": "125"}
{"id": "D4", "value": 64, "meta": "special note with em-dash —"}
EOF

    cat << 'EOF' > /home/user/project/process.py
import json

def cube_root(N):
    if N == 0: return 0.0
    x = N / 3.0 if N > 0 else -(-N / 3.0)
    for _ in range(100):
        fx = x**3 - N
        dfx = 3 * x**2
        # Update step for Newton's method
        x_new = x + fx / dfx
        if abs(x_new - x) < 1e-6:
            return round(x_new, 4)
        x = x_new
    raise ValueError(f"Convergence failure for N={N}")

def main():
    results = []
    # Read the data file
    with open('/home/user/project/data.jsonl', 'r', encoding='ascii') as f:
        for line in f:
            data = json.loads(line)
            N = float(data['value'])
            root = cube_root(N)
            results.append({"id": data["id"], "cube_root": root})

    # Write the results
    with open('/home/user/project/results.jsonl', 'w', encoding='utf-8') as f:
        for res in results:
            f.write(json.dumps(res) + '\n')

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
