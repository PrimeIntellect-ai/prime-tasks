#!/bin/bash
mkdir -p /logs/verifier

run_verification() {
    test -d /home/user/etl_processor || return 1
    test -f /home/user/etl_processor/Cargo.toml || return 1
    test -n "$(find /home/user/etl_processor -type f -name '*.rs' -size +0c -print -quit)" || return 1

    cat > /home/user/chat_logs.jsonl << 'EOF'
{"session_id": "S1", "timestamp": "2023-10-01T10:00:00Z", "message": "Hello \\u3053\\u3093\\u306b\\u3061\\u306f"}
{"session_id": "S2", "timestamp": "2023-10-01T10:01:00Z", "message": "Foo \\u2163"}
{"session_id": "S1", "timestamp": "2023-10-01T10:05:00Z", "message": "Bye"}
EOF

    cat > /home/user/tx_logs.jsonl << 'EOF'
{"session_id": "S1", "timestamp": 1696154410, "amount": 10.5}
{"session_id": "S1", "timestamp": 1696154450, "amount": 5.0}
{"session_id": "S1", "timestamp": 1696154470, "amount": 100.0}
{"session_id": "S2", "timestamp": 1696154465, "amount": 20.0}
{"session_id": "S1", "timestamp": 1696154760, "amount": 9.9}
EOF

    cargo build --manifest-path /home/user/etl_processor/Cargo.toml || return 1
    rm -f /home/user/output.jsonl
    timeout 120 cargo run --quiet --manifest-path /home/user/etl_processor/Cargo.toml || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import secrets
import subprocess
import unicodedata
from datetime import datetime, timezone

import pytest


def read_output(path="/home/user/output.jsonl"):
    assert os.path.exists(path), f"Output file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    actual = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    actual.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON line in {path}: {line}")
    return actual


def test_01_output_exists_and_correct():
    path = "/home/user/output.jsonl"
    assert os.path.exists(path), f"Output file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."

    expected = [
        {"session_id": "S1", "normalized_message": "Hello こんにちは", "chat_ts": 1696154400, "tx_sum": 15.5},
        {"session_id": "S2", "normalized_message": "Foo IV", "chat_ts": 1696154460, "tx_sum": 20.0},
        {"session_id": "S1", "normalized_message": "Bye", "chat_ts": 1696154700, "tx_sum": 9.9}
    ]

    actual = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    actual.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON line in {path}: {line}")

    assert len(actual) == len(expected), f"Expected {len(expected)} lines in output, got {len(actual)}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act.get("session_id") == exp["session_id"], \
            f"Line {i+1}: expected session_id '{exp['session_id']}', got '{act.get('session_id')}'"
        assert act.get("normalized_message") == exp["normalized_message"], \
            f"Line {i+1}: expected normalized_message '{exp['normalized_message']}', got '{act.get('normalized_message')}'"
        assert act.get("chat_ts") == exp["chat_ts"], \
            f"Line {i+1}: expected chat_ts {exp['chat_ts']}, got {act.get('chat_ts')}"
        assert act.get("tx_sum") == pytest.approx(exp["tx_sum"]), \
            f"Line {i+1}: expected tx_sum {exp['tx_sum']}, got {act.get('tx_sum')}"


def test_02_program_processes_runtime_fixture():
    base = 1700000000 + secrets.randbelow(1000000)
    sid_a = "A_" + secrets.token_hex(8)
    sid_b = "B_" + secrets.token_hex(8)
    sid_c = "C_" + secrets.token_hex(8)

    def iso(ts):
        return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    chats = [
        {"session_id": sid_a, "timestamp": iso(base + 120), "message": r"Last \uFF41"},
        {"session_id": sid_a, "timestamp": iso(base), "message": r"First \u2163 \uFF21"},
        {"session_id": sid_b, "timestamp": iso(base + 30), "message": r"Cafe\u0301"},
        {"session_id": sid_c, "timestamp": iso(base), "message": r"Tie \uFB03"},
        {"session_id": sid_a, "timestamp": iso(base + 60), "message": "Middle"},
    ]
    txs = [
        {"session_id": sid_a, "timestamp": base, "amount": 500.0},
        {"session_id": sid_a, "timestamp": base + 1, "amount": 1.25},
        {"session_id": sid_a, "timestamp": base + 60, "amount": 2.75},
        {"session_id": sid_a, "timestamp": base + 61, "amount": 9.5},
        {"session_id": sid_a, "timestamp": base + 120, "amount": 4.0},
        {"session_id": sid_b, "timestamp": base + 30, "amount": 100.0},
        {"session_id": sid_b, "timestamp": base + 31, "amount": 3.5},
        {"session_id": sid_b, "timestamp": base + 90, "amount": 6.5},
        {"session_id": sid_b, "timestamp": base + 91, "amount": 200.0},
        {"session_id": sid_c, "timestamp": base + 10, "amount": -2.25},
        {"session_id": "unrelated_" + secrets.token_hex(4), "timestamp": base + 5, "amount": 999.0},
    ]

    with open("/home/user/chat_logs.jsonl", "w", encoding="utf-8") as f:
        for row in chats:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    with open("/home/user/tx_logs.jsonl", "w", encoding="utf-8") as f:
        for row in txs:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    try:
        os.remove("/home/user/output.jsonl")
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", "/home/user/etl_processor/Cargo.toml"],
        cwd="/home/user/etl_processor",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"Program failed on runtime fixture:\n{result.stderr}"

    unicode_escape = re.compile(r"\\u([0-9a-fA-F]{4})")

    def normalize(message):
        decoded = unicode_escape.sub(lambda m: chr(int(m.group(1), 16)), message)
        return unicodedata.normalize("NFKC", decoded)

    indexed = []
    for index, chat in enumerate(chats):
        ts = int(datetime.strptime(chat["timestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
        total = sum(
            tx["amount"] for tx in txs
            if tx["session_id"] == chat["session_id"] and ts < tx["timestamp"] <= ts + 60
        )
        indexed.append((ts, index, {
            "session_id": chat["session_id"],
            "normalized_message": normalize(chat["message"]),
            "chat_ts": ts,
            "tx_sum": total,
        }))
    expected = [row for _, _, row in sorted(indexed, key=lambda item: (item[0], item[1]))]
    actual = read_output()

    assert len(actual) == len(expected)
    for i, (act, exp) in enumerate(zip(actual, expected), 1):
        assert set(act.keys()) == {"session_id", "normalized_message", "chat_ts", "tx_sum"}, f"Line {i}: wrong fields"
        assert act["session_id"] == exp["session_id"], f"Line {i}: wrong session_id"
        assert act["normalized_message"] == exp["normalized_message"], f"Line {i}: wrong normalized_message"
        assert act["chat_ts"] == exp["chat_ts"], f"Line {i}: wrong chat_ts or sorting"
        assert isinstance(act["tx_sum"], (int, float)) and not isinstance(act["tx_sum"], bool)
        assert act["tx_sum"] == pytest.approx(exp["tx_sum"]), f"Line {i}: wrong tx_sum"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
