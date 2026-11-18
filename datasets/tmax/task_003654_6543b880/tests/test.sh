#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import copy
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid
from collections import Counter
from pathlib import Path

RAW_LOGS_PATH = Path("/home/user/raw_logs.jsonl")
CLEAN_LOGS_PATH = Path("/home/user/clean_logs.jsonl")
TEMPLATE_PATH = Path("/home/user/report_template.html")
SUMMARY_PATH = Path("/home/user/summary.html")
HOME = Path("/home/user")


def find_rust_runner():
    manifests = []
    preferred = HOME / "log_processor" / "Cargo.toml"
    if preferred.is_file():
        manifests.append(preferred)

    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"target", ".cargo", ".git"}]
        candidate = Path(root) / "Cargo.toml"
        if "Cargo.toml" in files and candidate not in manifests:
            manifests.append(candidate)

    for manifest in manifests:
        project = manifest.parent
        rust_sources = [p for p in project.rglob("*.rs") if "target" not in p.parts]
        if rust_sources:
            subprocess.run(
                ["cargo", "build", "--quiet", "--manifest-path", str(manifest)],
                cwd=project,
                check=True,
                timeout=180,
            )
            return ["cargo", "run", "--quiet", "--manifest-path", str(manifest)], project

    main_sources = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"target", ".cargo", ".git"}]
        if "main.rs" in files:
            main_sources.append(Path(root) / "main.rs")

    if main_sources:
        source = sorted(main_sources, key=lambda p: (len(p.parts), str(p)))[0]
        binary = Path(tempfile.gettempdir()) / "submitted_log_processor"
        subprocess.run(
            ["rustc", str(source), "-o", str(binary)],
            cwd=source.parent,
            check=True,
            timeout=180,
        )
        return [str(binary)], source.parent

    raise AssertionError("No compilable Rust program was found under /home/user.")


def get_expected_data(raw_path=RAW_LOGS_PATH):
    assert raw_path.exists(), f"Input file {raw_path} is missing."
    lines = raw_path.read_text().strip().splitlines()
    total_raw = len(lines)
    seen_hashes = set()
    unique_logs = []
    actions = []

    for line in lines:
        if not line.strip():
            continue
        entry = json.loads(line)
        action = entry.get("action", "")
        status = entry.get("status", "")
        email = entry.get("email", "")
        key_hash = hashlib.sha256(f"{action}-{status}-{email}".encode("utf-8")).hexdigest()

        if key_hash not in seen_hashes:
            seen_hashes.add(key_hash)
            ip = entry.get("ip", "")
            if ip.count(".") == 3:
                entry["ip"] = f"XXX.XXX.XXX.{ip.split('.')[-1]}"
            if "@" in email:
                entry["email"] = f"***@{email.split('@')[1]}"
            unique_logs.append(entry)
            actions.append(action)

    top_action = Counter(actions).most_common(1)[0][0] if actions else ""
    return total_raw, len(unique_logs), top_action, unique_logs


def assert_outputs():
    assert CLEAN_LOGS_PATH.is_file(), f"Output file {CLEAN_LOGS_PATH} was not created."
    assert SUMMARY_PATH.is_file(), f"Output file {SUMMARY_PATH} was not created."
    assert TEMPLATE_PATH.is_file(), f"Template file {TEMPLATE_PATH} is missing."

    total_raw, total_unique, top_action, expected_unique_logs = get_expected_data()
    actual_lines = CLEAN_LOGS_PATH.read_text().strip().splitlines()
    assert len(actual_lines) == len(expected_unique_logs), (
        f"Expected {len(expected_unique_logs)} unique logs, but found "
        f"{len(actual_lines)} in {CLEAN_LOGS_PATH}."
    )

    for i, (actual_line, expected_entry) in enumerate(zip(actual_lines, expected_unique_logs)):
        try:
            actual_entry = json.loads(actual_line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Line {i + 1} in {CLEAN_LOGS_PATH} is not valid JSON.") from exc
        assert actual_entry == expected_entry, (
            f"Log entry at line {i + 1} does not match expected masked/deduplicated entry.\n"
            f"Expected: {expected_entry}\nActual: {actual_entry}"
        )

    template_content = TEMPLATE_PATH.read_text()
    expected_summary = template_content.replace("{{TOTAL_RAW}}", str(total_raw))
    expected_summary = expected_summary.replace("{{TOTAL_UNIQUE}}", str(total_unique))
    expected_summary = expected_summary.replace("{{TOP_ACTION}}", top_action)
    actual_summary = SUMMARY_PATH.read_text()
    assert actual_summary.strip() == expected_summary.strip(), (
        f"Content of {SUMMARY_PATH} does not match expected output with replaced placeholders."
    )


def run_processor(command, cwd):
    for output in (CLEAN_LOGS_PATH, SUMMARY_PATH):
        if output.exists():
            output.unlink()
    subprocess.run(command, cwd=cwd, check=True, timeout=60)
    assert_outputs()


def write_case(entries, template):
    RAW_LOGS_PATH.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    TEMPLATE_PATH.write_text(template)


def main():
    assert RAW_LOGS_PATH.is_file(), f"Input file {RAW_LOGS_PATH} is missing."
    assert TEMPLATE_PATH.is_file(), f"Template file {TEMPLATE_PATH} is missing."

    originals = {
        RAW_LOGS_PATH: RAW_LOGS_PATH.read_bytes(),
        TEMPLATE_PATH: TEMPLATE_PATH.read_bytes(),
    }
    command, cwd = find_rust_runner()

    try:
        # Execute the submitted Rust processor on the original fixture and retain
        # all of the original verifier's exact output checks.
        run_processor(command, cwd)

        nonce = uuid.uuid4().hex
        alpha = f"ALPHA_{nonce}"
        beta = f"BETA_{nonce}"
        gamma = f"GAMMA_{nonce}"
        delta = f"DELTA_{nonce}"
        domain = f"{nonce}.example.test"

        first_case = [
            {"timestamp": "2041-01-01T00:00:00Z", "ip": "11.22.33.41", "email": f"one@{domain}", "action": alpha, "status": 207},
            {"timestamp": "2041-01-01T00:01:00Z", "ip": "44.55.66.42", "email": f"two@{domain}", "action": beta, "status": 418},
            {"timestamp": "2041-01-01T00:02:00Z", "ip": "77.88.99.43", "email": f"one@{domain}", "action": alpha, "status": 207},
            {"timestamp": "2041-01-01T00:03:00Z", "ip": "101.102.103.44", "email": f"three@{domain}", "action": alpha, "status": 207},
            {"timestamp": "2041-01-01T00:04:00Z", "ip": "121.122.123.45", "email": f"four@{domain}", "action": gamma, "status": 503},
            {"timestamp": "2041-01-01T00:05:00Z", "ip": "131.132.133.46", "email": f"five@{domain}", "action": delta, "status": 201},
        ]
        write_case(
            first_case,
            f"<html><body data-token='{nonce}'>raw={{{{TOTAL_RAW}}}}; unique={{{{TOTAL_UNIQUE}}}}; top={{{{TOP_ACTION}}}}</body></html>\n",
        )
        run_processor(command, cwd)

        second_case = [
            {"timestamp": "2052-06-01T12:00:00Z", "ip": "1.2.3.91", "email": f"a@second-{domain}", "action": alpha, "status": 200},
            {"timestamp": "2052-06-01T12:01:00Z", "ip": "4.5.6.92", "email": f"b@second-{domain}", "action": alpha, "status": 201},
            {"timestamp": "2052-06-01T12:02:00Z", "ip": "7.8.9.93", "email": f"c@second-{domain}", "action": beta, "status": 400},
            {"timestamp": "2052-06-01T12:03:00Z", "ip": "10.11.12.94", "email": f"d@second-{domain}", "action": alpha, "status": 202},
            {"timestamp": "2052-06-01T12:04:00Z", "ip": "13.14.15.95", "email": f"b@second-{domain}", "action": alpha, "status": 201},
        ]
        write_case(
            second_case,
            f"TOKEN:{nonce}\nTOTAL={{{{TOTAL_RAW}}}}\nUNIQUE={{{{TOTAL_UNIQUE}}}}\nACTION={{{{TOP_ACTION}}}}\n",
        )
        run_processor(command, cwd)
    finally:
        for path, content in originals.items():
            path.write_bytes(content)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
