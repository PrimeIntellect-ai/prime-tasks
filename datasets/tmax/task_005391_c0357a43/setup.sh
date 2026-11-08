#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs
    pip3 install pytest

    mkdir -p /home/user/legacy /home/user/build_tools /home/user/artifacts

    cat << 'EOF' > /home/user/legacy/artifact_hasher.js
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');

function getBundleHash(dirPath) {
    const files = fs.readdirSync(dirPath).sort();
    let concatenatedHashes = "";
    for (const file of files) {
        const fullPath = path.join(dirPath, file);
        if (fs.statSync(fullPath).isFile()) {
            const fileBuffer = fs.readFileSync(fullPath);
            const hashSum = crypto.createHash('sha256');
            hashSum.update(fileBuffer);
            concatenatedHashes += hashSum.digest('hex');
        }
    }
    const finalHash = crypto.createHash('sha256');
    finalHash.update(concatenatedHashes);
    return finalHash.digest('hex');
}

const dir = process.argv[2];
if (dir) {
    console.log(getBundleHash(dir));
}
EOF

    echo "dummy data 1" > /home/user/artifacts/app-v1.0.tar.gz
    echo "another artifact here" > /home/user/artifacts/library.jar
    echo "meta information" > /home/user/artifacts/metadata.json

    cat << 'EOF' > /tmp/compute_truth.py
import os
import hashlib

def hash_dir(d):
    files = sorted(os.listdir(d))
    concat = ""
    for f in files:
        p = os.path.join(d, f)
        if os.path.isfile(p):
            with open(p, 'rb') as f_in:
                concat += hashlib.sha256(f_in.read()).hexdigest()
    return hashlib.sha256(concat.encode('utf-8')).hexdigest()

with open('/tmp/expected_manifest.txt', 'w') as f_out:
    f_out.write(hash_dir('/home/user/artifacts'))
EOF
    python3 /tmp/compute_truth.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
