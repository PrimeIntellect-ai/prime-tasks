#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'JSON' > /home/user/raw_logs.jsonl
{"timestamp": 1600000000, "service": "auth", "message": "User logged in \u0065\u0301", "metrics": {"response_time_ms": 120.0, "cpu_load": 0.45}}
{"timestamp": 1600000010, "service": "auth", "message": "Token check", "metrics": {"response_time_ms": null, "cpu_load": 0.50}}
{"timestamp": 1600000020, "service": "auth", "message": "Password mismatch \u00e9", "metrics": {"response_time_ms": 200.0, "cpu_load": 0.60}}
{"timestamp": 1600000005, "service": "db", "message": "Query OK \u006f\u0308", "metrics": {"response_time_ms": 45.0, "cpu_load": 0.80}}
{"timestamp": 1600000015, "service": "db", "message": "[FATAL] Deadlock detected \u00f6", "metrics": {"response_time_ms": 5000.0, "cpu_load": null}}
{"timestamp": 1600000035, "service": "db", "message": "Restarting \u00f6", "metrics": {"response_time_ms": 20.0, "cpu_load": 0.95}}
{"timestamp": 1600000045, "service": "auth", "message": "[FATAL] DB connection lost \u00e9", "metrics": {"response_time_ms": 3000.0, "cpu_load": 0.99}}
{invalid_json_here]
{"timestamp": 1600000050, "message": "Missing service field", "metrics": {"response_time_ms": 10.0, "cpu_load": 0.1}}
JSON

    chmod -R 777 /home/user
