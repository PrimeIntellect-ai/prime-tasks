#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_processor/logs

    cat << 'EOF' > /home/user/log_processor/parser.js
const fs = require('fs');
const file = process.argv[2];
const content = fs.readFileSync(file, 'utf8').trim().split('\n');
let jsonOutput = [];
for (let line of content) {
    if (!line) continue;
    let match = line.match(/^\[(.*?)\]\s+(\w+)\s+(.*)$/);
    if (match) {
        let msg = match[3];
        // BUG: manual JSON string construction doesn't escape double quotes in 'msg'
        let jsonStr = `{"timestamp": "${match[1]}", "level": "${match[2]}", "message": "${msg}"}`;
        jsonOutput.push(jsonStr);
    }
}
console.log("[" + jsonOutput.join(",") + "]");
EOF

    cat << 'EOF' > /home/user/log_processor/app.py
import os
import subprocess
import json

LOG_DIR = '/home/user/log_processor/logs'
OUTPUT_FILE = '/home/user/log_processor/output.json'

def process_logs():
    all_logs = []
    for filename in sorted(os.listdir(LOG_DIR)):
        if filename.endswith('.log'):
            filepath = os.path.join(LOG_DIR, filename)
            print(f"Processing {filename}...")
            result = subprocess.run(['node', '/home/user/log_processor/parser.js', filepath], capture_output=True, text=True)
            if result.returncode != 0:
                print(f"Node script failed for {filename}")
                continue

            try:
                parsed_data = json.loads(result.stdout)
                all_logs.extend(parsed_data)
            except json.JSONDecodeError as e:
                print(f"Failed to decode JSON from {filename}")
                print(f"Raw output was: {result.stdout}")
                raise e

    with open(OUTPUT_FILE, 'w') as f:
        json.dump(all_logs, f, indent=2)
    print(f"Successfully wrote {len(all_logs)} entries to {OUTPUT_FILE}")

if __name__ == "__main__":
    process_logs()
EOF

    for i in $(seq -w 1 10); do
        if [ "$i" == "07" ]; then
            cat << EOF > /home/user/log_processor/logs/server_07.log
[2023-10-07 10:00:00] INFO Starting server process
[2023-10-07 10:05:22] ERROR Failed to parse user input "admin" from payload
EOF
        else
            cat << EOF > /home/user/log_processor/logs/server_$i.log
[2023-10-$i 08:00:00] INFO Routine health check passed
[2023-10-$i 08:15:00] WARN High memory usage detected
EOF
        fi
    done

    chown -R user:user /home/user/log_processor
    chmod -R 777 /home/user
