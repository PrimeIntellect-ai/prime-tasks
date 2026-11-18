#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/monorepo/core_cpp
    cat << 'EOF' > /home/user/monorepo/core_cpp/manifest.json
{
  "name": "core_cpp",
  "deps": [],
  "build_steps": [
    "g++ main.cpp -o main",
    "./main"
  ]
}
EOF
    cat << 'EOF' > /home/user/monorepo/core_cpp/main.cpp
#include <iostream>
#include <fstream>
int main() {
    std::ofstream out("output.json");
    out << "{\"module\": \"core_cpp\", \"status\": \"compiled\", \"value\": 42}";
    out.close();
    return 0;
}
EOF

    mkdir -p /home/user/monorepo/utils_py
    cat << 'EOF' > /home/user/monorepo/utils_py/manifest.json
{
  "name": "utils_py",
  "deps": [],
  "build_steps": [
    "python3 script.py"
  ]
}
EOF
    cat << 'EOF' > /home/user/monorepo/utils_py/script.py
import json
with open("output.json", "w") as f:
    json.dump({"module": "utils_py", "status": "interpreted", "value": 10}, f)
EOF

    mkdir -p /home/user/monorepo/aggregator_py
    cat << 'EOF' > /home/user/monorepo/aggregator_py/manifest.json
{
  "name": "aggregator_py",
  "deps": ["core_cpp", "utils_py"],
  "build_steps": [
    "python3 agg.py"
  ]
}
EOF
    cat << 'EOF' > /home/user/monorepo/aggregator_py/agg.py
import json
import os

with open("../core_cpp/output.json") as f:
    c_data = json.load(f)
with open("../utils_py/output.json") as f:
    u_data = json.load(f)

with open("output.json", "w") as f:
    json.dump({
        "module": "aggregator_py", 
        "sum": c_data["value"] + u_data["value"],
        "dependencies_met": True
    }, f)
EOF

    mkdir -p /home/user/monorepo/final_cpp
    cat << 'EOF' > /home/user/monorepo/final_cpp/manifest.json
{
  "name": "final_cpp",
  "deps": ["aggregator_py"],
  "build_steps": [
    "g++ final.cpp -o final",
    "./final"
  ]
}
EOF
    cat << 'EOF' > /home/user/monorepo/final_cpp/final.cpp
#include <iostream>
#include <fstream>
int main() {
    std::ofstream out("output.json");
    out << "{\"module\": \"final_cpp\", \"complete\": true}";
    out.close();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
