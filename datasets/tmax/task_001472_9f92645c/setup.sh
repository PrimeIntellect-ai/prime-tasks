#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq bc
    pip3 install pytest flask

    mkdir -p /app

    # Create Feature Store service
    cat << 'EOF' > /app/feature_store.py
from flask import Flask, request, jsonify
import random

app = Flask(__name__)

@app.route('/features')
def features():
    ds_id = request.args.get('id', '')
    random.seed(ds_id)
    vec = []
    for _ in range(20):
        if random.random() < 0.2:
            vec.append(None)
        else:
            vec.append(round(random.uniform(-10.0, 10.0), 2))
    return jsonify(vec)

@app.route('/')
def index():
    return "OK"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
EOF

    # Create Candidate Catalog service
    cat << 'EOF' > /app/candidate_catalog.py
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/candidates')
def candidates():
    # Return a fixed list of candidate IDs
    return jsonify([f"DS{i:03d}" for i in range(100, 120)])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002)
EOF

    # Create Oracle script
    cat << 'EOF' > /app/oracle_recommender.sh
#!/bin/bash
while read -r query_id threshold; do
    [ -z "$query_id" ] && continue

    query_json=$(curl -s "http://127.0.0.1:5001/features?id=${query_id}")
    candidates=$(curl -s "http://127.0.0.1:5002/candidates" | jq -r '.[]')

    results=""
    for cand in $candidates; do
        cand_json=$(curl -s "http://127.0.0.1:5001/features?id=${cand}")
        cov=$(jq -n --argjson q "$query_json" --argjson c "$cand_json" '
            ($q | map(if . == null then 0 else . end)) as $a |
            ($c | map(if . == null then 0 else . end)) as $b |
            ($a | length) as $n |
            (($a | add) / $n) as $ma |
            (($b | add) / $n) as $mb |
            [range($n)] | map(($a[.] - $ma) * ($b[.] - $mb)) | add / $n
        ')
        pass=$(echo "$cov >= $threshold" | bc -l)
        if [ "$pass" -eq 1 ]; then
            formatted_cov=$(printf "%.3f" "$cov")
            results+="${query_id} -> ${cand}: ${formatted_cov}"$'\n'
        fi
    done
    if [ -n "$results" ]; then
        echo -n "$results" | sort -t' ' -k4,4nr -k3,3
    fi
done
EOF

    chmod +x /app/oracle_recommender.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
