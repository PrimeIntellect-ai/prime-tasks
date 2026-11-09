#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs curl
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/ingester.py
import sys
import os
import json

# The system should run in production mode to use proper serialization
mode = os.environ.get("PIPELINE_MODE", "legacy")

data = {"status": "critical", "payload": "alert data", "tags": ["urgent", "nightly"]}

if mode == "legacy":
    # Legacy mode outputs malformed JSON (deliberate serialization issue)
    # Notice the trailing comma in the array, which is invalid JSON
    out = '{"status": "critical", "payload": "alert data", "tags": ["urgent", "nightly", ]}'
else:
    # Production mode outputs valid JSON
    out = json.dumps(data)

print(out)
EOF

    cat << 'EOF' > /home/user/pipeline/processor.js
const fs = require('fs');
const data = fs.readFileSync(0, 'utf-8');

function resilientParse(str, attempt = 0) {
    try {
        return JSON.parse(str);
    } catch (e) {
        if (attempt < 5) {
            // Attempt to fix trailing commas in objects
            let fixed = str.replace(/,(\s*)}/g, '$1}');
            // BUG: attempt is not incremented, causing infinite recursion on RangeError
            // if the string has an array trailing comma like `,]`, the regex misses it.
            return resilientParse(fixed, attempt); 
        }
        throw e;
    }
}

try {
    const parsed = resilientParse(data);
    console.log("SUCCESS:", parsed.status);
} catch (e) {
    console.error(e);
    process.exit(1);
}
EOF

    cat << 'EOF' > /home/user/pipeline/run_pipeline.sh
#!/bin/bash
# Pipeline runner script
# Missing environment variable: PIPELINE_MODE=production

python3 /home/user/pipeline/ingester.py | node /home/user/pipeline/processor.js
EOF

    chmod +x /home/user/pipeline/run_pipeline.sh
    chmod +x /home/user/pipeline/ingester.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
