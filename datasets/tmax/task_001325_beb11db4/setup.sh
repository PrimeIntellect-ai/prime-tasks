#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb cargo jq
    pip3 install pytest

    # Create directories
    mkdir -p /app/data/clean_samples
    mkdir -p /app/data/evil_samples
    mkdir -p /app/test_corpora/clean
    mkdir -p /app/test_corpora/evil

    # Create dummy C program
    cat << 'EOF' > /tmp/engine.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    const char* s1 = "$graphLookup";
    const char* s2 = "maxDepth";
    const char* s3 = "$lookup";
    const char* s4 = "pipeline";
    int max_depth_limit = 5;

    if (argc > 1) {
        printf("Processing %s\n", argv[1]);
    }
    return 0;
}
EOF
    gcc -O2 /tmp/engine.c -o /app/graph_engine
    strip /app/graph_engine

    # Generate JSON data
    cat << 'EOF' > /tmp/gen_data.py
import json
import os

def write_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f)

# Clean samples
write_json('/app/data/clean_samples/1.json', [{"$match": {"status": "A"}}, {"$graphLookup": {"from": "employees", "startWith": "$reportsTo", "connectFromField": "reportsTo", "connectToField": "name", "as": "reportingHierarchy", "maxDepth": 3}}])
write_json('/app/data/clean_samples/2.json', [{"$lookup": {"from": "inventory", "localField": "item", "foreignField": "sku", "as": "inventory_docs"}}])
write_json('/app/data/clean_samples/3.json', [{"$graphLookup": {"maxDepth": 5}}])

# Evil samples
write_json('/app/data/evil_samples/1.json', [{"$graphLookup": {"from": "employees"}}])
write_json('/app/data/evil_samples/2.json', [{"$graphLookup": {"maxDepth": 6}}])
write_json('/app/data/evil_samples/3.json', [{"$lookup": {"pipeline": [{"$lookup": {}}]}}])

# Corpora
for i in range(50):
    write_json(f'/app/test_corpora/clean/{i}.json', [{"$graphLookup": {"maxDepth": i % 6}}])

for i in range(50):
    if i % 2 == 0:
        write_json(f'/app/test_corpora/evil/{i}.json', [{"$graphLookup": {"maxDepth": 6 + i}}])
    else:
        write_json(f'/app/test_corpora/evil/{i}.json', [{"$lookup": {"pipeline": [{"$match": {}}, {"$lookup": {}}]}}])
EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
