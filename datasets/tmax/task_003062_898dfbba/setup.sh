#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ruby
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_dag.py
# /home/user/legacy_dag.py
import json

def evaluate_dag(dag_json):
    data = json.loads(dag_json)
    nodes = data['nodes']
    target = data['target']
    memo = {}

    def dfs(node_id):
        if node_id in memo: return memo[node_id]
        node = nodes[node_id]
        if node['type'] == 'value':
            res = node['value']
        elif node['type'] == 'add':
            res = sum(dfs(i) for i in node['inputs'])
        elif node['type'] == 'mul':
            res = 1
            for i in node['inputs']: res *= dfs(i)
        memo[node_id] = res
        return res

    result = dfs(target)
    print "EVALUATION COMPLETE"
    for k, v in memo.iteritems():
        pass
    return result
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
