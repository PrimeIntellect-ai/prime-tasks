#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import subprocess

RAW_PATH = Path("/home/user/raw_data.jsonl")
CSV_PATH = Path("/home/user/features.csv")
FIXTURE = b'''{"doc_id": 1, "content": "Machine learning is fun"}\n{"doc_id": 2, "content": "Rust systems programming"}\n{"doc_id": "three", "content": "Invalid schema"}\n{"doc_id": 4, "content": "Learning machine systems"}\n{"doc_id": 5, "content": "fun fun fun"}\n{"id": 6, "content": "Wrong field name"}\n'''


def expected_lines(raw_bytes, enforce_u32_upper=False):
    expected_rows = []
    for line in raw_bytes.decode("utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        if "doc_id" not in data or "content" not in data:
            continue
        if not isinstance(data["doc_id"], int) or isinstance(data["doc_id"], bool) or data["doc_id"] < 0:
            continue
        if enforce_u32_upper and data["doc_id"] > 0xFFFFFFFF:
            continue
        if not isinstance(data["content"], str):
            continue

        counts = [0, 0, 0, 0]
        for token in data["content"].lower().split():
            counts[sum(ord(c) for c in token) % 4] += 1
        expected_rows.append((data["doc_id"], counts))

    expected_rows.sort(key=lambda row: row[0])
    lines = ["doc_id,f0,f1,f2,f3"]
    lines.extend(f"{doc_id},{counts[0]},{counts[1]},{counts[2]},{counts[3]}"
                 for doc_id, counts in expected_rows)
    return lines


def read_csv_lines():
    with CSV_PATH.open("r") as f:
        return [line.strip() for line in f if line.strip()]


def test_raw_fixture_is_unchanged():
    assert RAW_PATH.exists(), f"{RAW_PATH} is missing. Did you delete or move the input data?"
    assert RAW_PATH.is_file(), f"{RAW_PATH} is not a file."
    assert RAW_PATH.read_bytes() == FIXTURE, "The setup input fixture was modified."


def test_features_csv_exists_and_correct():
    csv_path = str(CSV_PATH)
    assert os.path.exists(csv_path), f"{csv_path} does not exist. The Rust program may not have run successfully or output to the wrong location."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

    raw_path = str(RAW_PATH)
    assert os.path.exists(raw_path), f"{raw_path} is missing. Did you delete or move the input data?"

    expected_csv_lines = expected_lines(RAW_PATH.read_bytes())
    actual_lines = read_csv_lines()

    assert actual_lines == expected_csv_lines, (
        f"CSV content mismatch.\n"
        f"Expected {len(expected_csv_lines)} lines, got {len(actual_lines)} lines.\n"
        f"Expected:\n{expected_csv_lines}\n"
        f"Got:\n{actual_lines}"
    )


def find_cargo_projects():
    manifests = []
    for root in (Path("/home/user"), Path("/workspace"), Path("/tmp")):
        if not root.exists():
            continue
        for manifest in root.rglob("Cargo.toml"):
            parts = set(manifest.parts)
            if "target" in parts or ".cargo" in parts:
                continue
            src = manifest.parent / "src"
            if src.is_dir() and any(src.rglob("*.rs")):
                manifests.append(manifest)
    preferred = Path("/home/user/preprocessor/Cargo.toml")
    return sorted(set(manifests), key=lambda p: (p != preferred, str(p)))


def test_rust_program_executes_on_unseen_input():
    manifests = find_cargo_projects()
    assert manifests, "No runnable Rust Cargo project with Rust source was found."

    hidden_raw = b'''{"doc_id":42,"content":"A a\\tb"}\n{"doc_id":0,"content":"Rust SYSTEMS  fun"}\n{"doc_id":4000000000,"content":"z z!"}\n{"doc_id":17,"content":""}\n{"doc_id":true,"content":"invalid bool"}\n{"doc_id":4294967296,"content":"outside u32"}\n{"doc_id":8,"content":12}\n{"content":"missing id"}\nnot json\n'''
    expected = expected_lines(hidden_raw, enforce_u32_upper=True)
    original_raw = RAW_PATH.read_bytes()
    original_csv = CSV_PATH.read_bytes()
    failures = []
    passed = False

    try:
        for manifest in manifests:
            RAW_PATH.write_bytes(hidden_raw)
            if CSV_PATH.exists():
                CSV_PATH.unlink()

            env = os.environ.copy()
            env["HOME"] = "/home/user"
            try:
                result = subprocess.run(
                    ["cargo", "run", "--quiet", "--manifest-path", str(manifest)],
                    cwd=str(manifest.parent), env=env, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
                )
            except Exception as exc:
                failures.append(f"{manifest}: {exc}")
                continue

            if result.returncode != 0:
                failures.append(f"{manifest}: cargo run failed: {result.stderr[-500:]}")
                continue
            if not CSV_PATH.is_file():
                failures.append(f"{manifest}: did not create {CSV_PATH}")
                continue
            actual = read_csv_lines()
            if actual != expected:
                failures.append(f"{manifest}: output mismatch; expected {expected}, got {actual}")
                continue

            passed = True
            break
    finally:
        RAW_PATH.write_bytes(original_raw)
        CSV_PATH.write_bytes(original_csv)

    assert passed, "No Rust project produced correct output when executed. " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
