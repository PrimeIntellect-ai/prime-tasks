#!/bin/bash
set -uo pipefail
mkdir -p /logs/verifier

TMPDIR=$(mktemp -d)
OUTPUT_FILE=/home/user/unique_network_configs.txt
SCRIPT_FILE=/home/user/process_configs.sh

cleanup() {
    rm -rf /home/user/logs
    if [ -d "$TMPDIR/original_logs" ]; then
        cp -a "$TMPDIR/original_logs" /home/user/logs
    fi
    rm -f "$OUTPUT_FILE"
    if [ -f "$TMPDIR/original_output" ]; then
        cp -a "$TMPDIR/original_output" "$OUTPUT_FILE"
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

run_tests() {
    [ -f "$SCRIPT_FILE" ] && [ ! -L "$SCRIPT_FILE" ] || {
        echo "Missing regular Bash script: $SCRIPT_FILE" >&2
        return 1
    }
    [ -d /home/user/logs ] && [ ! -L /home/user/logs ] || {
        echo "/home/user/logs must be a real directory" >&2
        return 1
    }

    cp -a /home/user/logs "$TMPDIR/original_logs" || return 1
    if [ -f "$OUTPUT_FILE" ]; then
        cp -a "$OUTPUT_FILE" "$TMPDIR/original_output" || return 1
    fi

    # Ignore full-line comments when checking the implementation constraints.
    sed '/^[[:space:]]*#/d' "$SCRIPT_FILE" > "$TMPDIR/source.no_comments" || return 1
    if grep -Eiq '(^|[;&|()[:space:]])(/[^;&|()[:space:]]*/)?(jq|python([0-9.]*)?|perl|ruby|node(js)?)([;&|()[:space:]]|$)' "$TMPDIR/source.no_comments"; then
        echo "The submitted script uses a prohibited parser/runtime" >&2
        return 1
    fi

    # Accept the two normal coreutils/Bash parallelization strategies:
    # xargs -P, or background jobs followed by wait.
    if grep -Eq 'xargs.*[[:space:]]-P([[:space:]]*[0-9]+)?' "$TMPDIR/source.no_comments"; then
        :
    elif grep -Eq '&[[:space:]]*(;[[:space:]]*)?$' "$TMPDIR/source.no_comments" && \
         grep -Eq '(^|[;&[:space:]])wait([;&[:space:]]|$)' "$TMPDIR/source.no_comments"; then
        :
    else
        echo "No supported parallel-processing implementation was found (use xargs -P or Bash background jobs with wait)" >&2
        return 1
    fi

    # Recreate the fixed setup fixtures so the script itself, rather than a
    # prewritten output file, is tested against the original assertions.
    rm -rf /home/user/logs
    mkdir -p /home/user/logs
    chmod 777 /home/user/logs
    cat > /home/user/logs/node1.jsonl <<'EOF'
{"event": "update", "config_key": "network.proxy.url", "config_value": "http\u003a\u002f\u002fproxy.local\u003a8080", "timestamp": 1679921020}
{"event": "update", "config_key": "system.memory", "config_value": "1024", "timestamp": 1679921021}
{"event": "update", "config_key": "network.timeout", "config_value": "30", "timestamp": 1679921022}
EOF
    cat > /home/user/logs/node2.jsonl <<'EOF'
{"event": "update", "config_key": "network.proxy.url", "config_value": "http\u003a\u002f\u002fproxy.local\u003a8080", "timestamp": 1679921023}
{"event": "update", "config_key": "network.dns.primary", "config_value": "8.8.8.8", "timestamp": 1679921024}
{"event": "update", "config_key": "app.workers", "config_value": "4", "timestamp": 1679921025}
{"event": "update", "config_key": "network.host.tags", "config_value": "region\u003deast\u002cenv\u003dprod", "timestamp": 1679921026}
EOF
    cat > /home/user/logs/node3.jsonl <<'EOF'
{"event": "update", "config_key": "network.dns.primary", "config_value": "8.8.8.8", "timestamp": 1679921027}
{"event": "update", "config_key": "network.dns.secondary", "config_value": "8.8.4.4", "timestamp": 1679921028}
EOF
    chmod 644 /home/user/logs/*.jsonl
    rm -f "$OUTPUT_FILE"

    runuser -u user -- timeout 20 bash "$SCRIPT_FILE" || {
        echo "The submitted script failed on the setup fixtures" >&2
        return 1
    }

    cat > "$TMPDIR/test_final_state.py" <<'PY'
import os
import hashlib

OUTPUT_FILE = "/home/user/unique_network_configs.txt"

def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist. Did the script run successfully?"
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

def test_output_file_contents():
    expected_pairs = [
        "network.proxy.url=http://proxy.local:8080",
        "network.timeout=30",
        "network.dns.secondary=8.8.4.4",
        "network.dns.primary=8.8.8.8",
        "network.host.tags=region=east,env=prod"
    ]
    expected_lines = []
    for pair in expected_pairs:
        md5_hash = hashlib.md5(pair.encode('utf-8')).hexdigest()
        expected_lines.append(f"{md5_hash}  {pair}")
    expected_lines.sort()
    with open(OUTPUT_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {OUTPUT_FILE}, but found {len(actual_lines)}. "
        "Make sure deduplication is working correctly."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}\n"
            "Ensure the script correctly decodes unicode escapes, formats as '<hash>  key=value', and sorts by hash."
        )
PY
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$TMPDIR/test_final_state.py" -x --tb=short || return 1

    # Exercise the artifact again on unpredictable fixtures. This prevents a
    # submission from passing by merely writing the five known output lines.
    token=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n') || return 1
    rm -rf /home/user/logs
    mkdir -p /home/user/logs
    chmod 777 /home/user/logs
    cat > /home/user/logs/a.jsonl <<EOF
{"event":"update","config_key":"network.audit.$token","config_value":"edge\u003a\u002f\u002fhost\u003d$token","timestamp":1}
{"event":"update","config_key":"application.$token","config_value":"ignored","timestamp":2}
EOF
    cat > /home/user/logs/b.jsonl <<EOF
{"event": "update", "config_key": "network.flag.$token", "config_value": "left\u003dright\u002c$id", "timestamp": 3}
{"event":"update","config_key":"network.audit.$token","config_value":"edge\u003a\u002f\u002fhost\u003d$token","timestamp":4}
EOF
    cat > /home/user/logs/c.jsonl <<EOF
{"event":"update","config_key":"network.plain.$token","config_value":"value-$token","timestamp":5}
EOF
    chmod 644 /home/user/logs/*.jsonl
    rm -f "$OUTPUT_FILE"

    runuser -u user -- timeout 20 bash "$SCRIPT_FILE" || {
        echo "The submitted script failed on additional fixtures" >&2
        return 1
    }

    python3 - "$token" <<'PY' || return 1
import hashlib
import os
import sys

token = sys.argv[1]
pairs = [
    f"network.audit.{token}=edge://host={token}",
    f"network.flag.{token}=left=right,{os.getuid()}",
    f"network.plain.{token}=value-{token}",
]
expected = sorted(f"{hashlib.md5(p.encode()).hexdigest()}  {p}" for p in pairs)
path = "/home/user/unique_network_configs.txt"
assert os.path.isfile(path), f"{path} was not produced by the script"
with open(path, encoding="utf-8") as f:
    actual = [line.rstrip("\n") for line in f if line.strip()]
assert actual == expected, f"Additional-fixture output mismatch.\nExpected: {expected!r}\nActual: {actual!r}"
PY
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
