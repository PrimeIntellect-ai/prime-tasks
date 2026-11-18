#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import csv
import json
import os
import re
import secrets
import stat
import subprocess

HOME = "/home/user"
PROCESS = f"{HOME}/process.py"
MAKEFILE = f"{HOME}/Makefile"
METADATA = f"{HOME}/data/metadata.csv"
TEXTS = f"{HOME}/data/texts.jsonl"
OUTPUT = f"{HOME}/output/processed.jsonl"


def run(command):
    result = subprocess.run(
        command,
        cwd=HOME,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file does not exist at {OUTPUT}"
    with open(OUTPUT, "r", encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def assert_output(expected):
    data = read_output()
    assert len(data) == len(expected), f"Expected {len(expected)} records, got {len(data)}"
    for record in data:
        assert set(record) == {"doc_id", "category", "tokens"}, (
            f"Record has incorrect keys: {record}"
        )
        assert isinstance(record["doc_id"], str)
        assert isinstance(record["category"], str)
        assert isinstance(record["tokens"], list)
        assert all(isinstance(token, str) for token in record["tokens"])
    data.sort(key=lambda item: item["doc_id"])
    expected.sort(key=lambda item: item["doc_id"])
    assert data == expected, f"Data mismatch.\nExpected: {expected}\nGot: {data}"


def install_case(metadata_rows, text_rows):
    os.makedirs(os.path.dirname(METADATA), exist_ok=True)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(METADATA, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["doc_id", "category", "date"])
        writer.writeheader()
        writer.writerows(metadata_rows)
    with open(TEXTS, "w", encoding="utf-8") as handle:
        for row in text_rows:
            handle.write(json.dumps(row) + "\n")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    by_doc_id = {row["doc_id"]: row for row in metadata_rows}
    expected = []
    for text in text_rows:
        doc_id = f"DOC_{text['id']}"
        if doc_id in by_doc_id:
            expected.append({
                "doc_id": doc_id,
                "category": by_doc_id[doc_id]["category"],
                "tokens": re.findall(r"\b[a-z0-9]+\b", text["content"].lower()),
            })
    return expected


def test_complete_pipeline():
    assert os.path.isfile(MAKEFILE), f"Makefile does not exist at {MAKEFILE}"
    assert os.path.isfile(PROCESS), f"Python script does not exist at {PROCESS}"

    paths = [PROCESS, METADATA, TEXTS]
    backups = {path: open(path, "rb").read() for path in paths}
    process_mode = stat.S_IMODE(os.stat(PROCESS).st_mode)

    try:
        # Preserve the original fixed-fixture assertions.
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run(["make", "-C", HOME, "all"])
        assert_output([
            {"doc_id": "DOC_1", "category": "science", "tokens": ["the", "quick", "brown", "fox", "jumps", "over", "2", "lazy", "dogs"]},
            {"doc_id": "DOC_2", "category": "history", "tokens": ["history", "is", "written", "by", "the", "victors"]},
            {"doc_id": "DOC_3", "category": "art", "tokens": ["art", "is", "in", "the", "eye", "of", "the", "beholder"]},
        ])

        # Exercise process.py directly on unpredictable altered inputs.
        nonce = secrets.randbelow(800000000) + 100000000
        ids = [nonce, nonce + 7, nonce + 19]
        metadata_rows = [
            {"doc_id": f"DOC_{ids[1]}", "category": f"cat-{secrets.token_hex(5)}", "date": "2025-04-02"},
            {"doc_id": f"DOC_{ids[0]}", "category": f"cat-{secrets.token_hex(5)}", "date": "2025-04-01"},
            {"doc_id": f"DOC_{ids[2] + 1}", "category": "metadata-only", "date": "2025-04-03"},
        ]
        text_rows = [
            {"id": ids[0], "content": f"MiXeD-{nonce}! Alpha's BETA 007 end."},
            {"id": ids[2], "content": "This text has no matching metadata."},
            {"id": ids[1], "content": f"Tabs\tand punctuation; number{nonce + 7} plus 42."},
        ]
        expected = install_case(metadata_rows, text_rows)
        run(["python3", PROCESS])
        assert_output(expected)

        # Verify that the Makefile's all target actually invokes process.py,
        # while also testing a second independently generated dataset.
        nonce2 = secrets.randbelow(800000000) + 100000000
        metadata_rows2 = [
            {"doc_id": f"DOC_{nonce2 + 2}", "category": f"group-{secrets.token_hex(6)}", "date": "2026-01-02"},
            {"doc_id": f"DOC_{nonce2}", "category": f"group-{secrets.token_hex(6)}", "date": "2026-01-01"},
            {"doc_id": f"DOC_{nonce2 + 9}", "category": "unmatched", "date": "2026-01-09"},
        ]
        text_rows2 = [
            {"id": nonce2 + 2, "content": f"SECOND run: Code-{nonce2 + 2}, XYZ and 9000!"},
            {"id": nonce2 + 5, "content": "Unmatched text must disappear."},
            {"id": nonce2, "content": "LOWER upper 123; joined-record."},
        ]
        expected2 = install_case(metadata_rows2, text_rows2)

        marker = f"/tmp/process-ran-{secrets.token_hex(12)}"
        encoded_source = base64.b64encode(backups[PROCESS]).decode("ascii")
        wrapper = f'''#!/usr/bin/env python3
import base64
with open({marker!r}, "w", encoding="utf-8") as _marker:
    _marker.write("ran")
_source = base64.b64decode({encoded_source!r})
_globals = {{"__name__": "__main__", "__file__": "/home/user/process.py", "__package__": None}}
exec(compile(_source, "/home/user/process.py", "exec"), _globals)
'''
        with open(PROCESS, "w", encoding="utf-8") as handle:
            handle.write(wrapper)
        os.chmod(PROCESS, process_mode)

        run(["make", "-C", HOME, "all"])
        assert os.path.isfile(marker), "Makefile target 'all' did not invoke process.py"
        assert_output(expected2)
    finally:
        for path, content in backups.items():
            with open(path, "wb") as handle:
                handle.write(content)
        os.chmod(PROCESS, process_mode)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
