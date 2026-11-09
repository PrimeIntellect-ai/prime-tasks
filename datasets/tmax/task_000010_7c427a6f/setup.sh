#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/trace_analyzer.py
import json
import sys

def load_logs(filepath):
    entries = {}
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            data = json.loads(line.strip())
            entries[data['trace_id']] = data
    return entries

def get_full_trace(trace_id, entries):
    entry = entries[trace_id]
    if entry.get('parent_id'):
        return get_full_trace(entry['parent_id'], entries) + " -> " + entry['message']
    return entry['message']

def main():
    entries = load_logs('/home/user/app_trace.log')

    resolved_traces = {}
    for tid in entries:
        resolved_traces[tid] = get_full_trace(tid, entries)

    with open('/home/user/clean_traces.json', 'w') as f:
        json.dump(resolved_traces, f, indent=2)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/app_trace.log
{"trace_id": "T001", "parent_id": null, "message": "Init Process"}
{"trace_id": "T002", "parent_id": "T001", "message": "Auth Module"}
{"trace_id": "T003", "parent_id": "T004", "message": "Cyclic A"}
{"trace_id": "T004", "parent_id": "T003", "message": "Cyclic B"}
{"trace_id": "T005", "parent_id": "T002", "message": "DB Query"}
corrupted binary garbage \x00\x12\xff\xee
{"trace_id": "T0", "parent_id": null, "message": "Bad ID Format"}
{"trace_id": "T999", "parent_id": "T888", "message": "Missing Parent"}
{"trace_id": "T006", "parent_id": "T005", "message": "Render Response"}
{"trace_id": "X007", "parent_id": "T006", "message": "Bad ID Prefix"}
EOF

    chmod -R 777 /home/user
