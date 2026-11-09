#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl g++ nlohmann-json3-dev
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    mkdir -p /app
    cat << 'EOF' > /app/agg_oracle.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <algorithm>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream ifs(argv[1]);
    if (!ifs.is_open()) return 1;
    json j;
    try { ifs >> j; } catch (...) { return 1; }
    if (!j.is_array()) return 1;

    int lookup_count = 0;
    bool has_group = false;
    bool has_match_before_group = false;

    for (size_t i = 0; i < j.size(); ++i) {
        if (j[i].contains("$lookup")) lookup_count++;
        if (j[i].contains("$group")) has_group = true;
        if (j[i].contains("$match") && !has_group) has_match_before_group = true;
        if (i > 0 && j[i-1].contains("$lookup") && j[i].contains("$unwind")) return 1;
    }
    if (lookup_count > 2) return 1;
    if (has_group && !has_match_before_group) return 1;

    if (j.empty()) return 1;
    auto last = j.back();
    if (!last.contains("$project")) return 1;

    std::ifstream sfs("/home/user/target_schema.json");
    if (!sfs.is_open()) return 1;
    json schema;
    try { sfs >> schema; } catch (...) { return 1; }

    auto proj = last["$project"];
    std::vector<std::string> proj_keys;
    for (auto& el : proj.items()) proj_keys.push_back(el.key());
    std::vector<std::string> schema_keys = schema.get<std::vector<std::string>>();

    std::sort(proj_keys.begin(), proj_keys.end());
    std::sort(schema_keys.begin(), schema_keys.end());

    if (proj_keys != schema_keys) return 1;
    return 0;
}
EOF
    g++ -O3 /app/agg_oracle.cpp -o /app/agg_oracle
    strip /app/agg_oracle
    chmod +x /app/agg_oracle
    rm /app/agg_oracle.cpp

    useradd -m -s /bin/bash user || true

    # Make Rust available for user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup

    cat << 'EOF' > /tmp/gen_corpora.py
import json
import os
import random

clean_dir = "/home/user/corpora/clean"
evil_dir = "/home/user/corpora/evil"
os.makedirs(clean_dir, exist_ok=True)
os.makedirs(evil_dir, exist_ok=True)

schema = ["_id", "total_sales", "customer_name", "timestamp"]
with open("/home/user/target_schema.json", "w") as f:
    json.dump(schema, f)

def make_project():
    return {"$project": {k: 1 for k in schema}}

for i in range(50):
    pipeline = []
    if random.choice([True, False]):
        pipeline.append({"$match": {"status": "A"}})
    if random.choice([True, False]):
        pipeline.append({"$group": {"_id": "$item"}})
    if random.choice([True, False]):
        pipeline.append({"$lookup": {"from": "x"}})
        pipeline.append({"$match": {"x": 1}})
        pipeline.append({"$unwind": "$x"})
    pipeline.append(make_project())
    with open(f"{clean_dir}/{i}.json", "w") as f:
        json.dump(pipeline, f)

for i in range(50):
    pipeline = []
    typ = i % 5
    if typ == 0:
        pipeline.append({"$group": {"_id": "$item"}})
        pipeline.append(make_project())
    elif typ == 1:
        pipeline.append({"$lookup": {"from": "a"}})
        pipeline.append({"$lookup": {"from": "b"}})
        pipeline.append({"$lookup": {"from": "c"}})
        pipeline.append(make_project())
    elif typ == 2:
        pipeline.append({"$project": {"_id": 1}})
    elif typ == 3:
        pipeline.append({"$lookup": {"from": "a"}})
        pipeline.append({"$unwind": "$a"})
        pipeline.append(make_project())
    elif typ == 4:
        pipeline.append({"$match": {"status": "A"}})
    with open(f"{evil_dir}/{i}.json", "w") as f:
        json.dump(pipeline, f)
EOF
    python3 /tmp/gen_corpora.py
    rm /tmp/gen_corpora.py

    # Set up bashrc for user to have cargo in PATH
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /home/user/.bashrc

    chmod -R 777 /home/user
