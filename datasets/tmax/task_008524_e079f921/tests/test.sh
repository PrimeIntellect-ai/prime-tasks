#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess


def expected_report(raw_data_path):
    records = []
    seen_txids = set()

    pattern = re.compile(r"TxID:\s*(?P<txid>\w+)\s*\|\s*User:\s*(?P<user>[^|]+?)\s*\|\s*Card:\s*(?P<card>\d{16})\s*\|\s*Amount:\s*(?P<amount>[\d.]+)")

    with open(raw_data_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = pattern.search(line)
            if match:
                txid = match.group("txid")
                user = match.group("user").strip()
                card = match.group("card")
                amount = float(match.group("amount"))

                if txid not in seen_txids:
                    seen_txids.add(txid)
                    records.append({
                        "txid": txid,
                        "user": user,
                        "card": card,
                        "amount": amount,
                    })

    assert len(records) > 0, "No valid records found in raw data."

    amounts = [r["amount"] for r in records]
    min_amt = min(amounts)
    max_amt = max(amounts)
    expected_output_lines = []

    for i, r in enumerate(records):
        masked_card = r["card"][:4] + "********" + r["card"][12:]
        start_idx = max(0, i - 2)
        window = amounts[start_idx:i + 1]
        rolling_avg = sum(window) / len(window)

        if max_amt == min_amt:
            norm_amount = 0.0
        else:
            norm_amount = (r["amount"] - min_amt) / (max_amt - min_amt)

        expected_output_lines.append(f"REPORT FOR TX {r['txid']}")
        expected_output_lines.append(f"User: {r['user']}")
        expected_output_lines.append(f"Card: {masked_card}")
        expected_output_lines.append(f"Norm_Amount: {norm_amount:.4f}")
        expected_output_lines.append(f"Rolling_Avg: {rolling_avg:.4f}")
        expected_output_lines.append("---")

    return "\n".join(expected_output_lines) + "\n"


def test_clean_report_exists_and_correct():
    raw_data_path = "/home/user/raw_data.txt"
    report_path = "/home/user/clean_report.txt"

    assert os.path.isfile(raw_data_path), f"Input file {raw_data_path} is missing."
    assert os.path.isfile(report_path), f"Output file {report_path} is missing. Did you run the Rust program?"

    expected_output = expected_report(raw_data_path)
    with open(report_path, "r") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), (
        "The generated report does not match the expected output. "
        "Check deduplication, masking, rolling average, and normalization logic."
    )


def test_rust_project_builds_and_generates_report_for_fresh_input():
    project_path = "/home/user/etl_processor"
    manifest_path = os.path.join(project_path, "Cargo.toml")
    source_path = os.path.join(project_path, "src", "main.rs")
    raw_data_path = "/home/user/raw_data.txt"
    report_path = "/home/user/clean_report.txt"

    assert os.path.isdir(project_path), "The required Cargo project /home/user/etl_processor is missing."
    assert os.path.isfile(manifest_path), "Cargo.toml is missing from the Rust project."
    assert os.path.isfile(source_path), "src/main.rs is missing from the Rust binary project."

    with open(manifest_path, "r") as f:
        manifest_text = f.read()
    with open(source_path, "r") as f:
        source_text = f.read()

    assert re.search(r"(?m)^\s*regex\s*=", manifest_text), "The Cargo project must depend on the regex crate."
    assert "regex" in source_text and "Regex" in source_text, "The Rust application must parse records using a regular expression."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", manifest_path],
        cwd=project_path,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Cargo metadata failed:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    binary_targets = [
        target
        for package in metadata["packages"]
        for target in package["targets"]
        if "bin" in target.get("kind", [])
    ]
    assert binary_targets, "The Cargo project does not define a Rust binary target."
    binary_name = binary_targets[0]["name"]

    original_raw = open(raw_data_path, "rb").read()
    original_report = open(report_path, "rb").read()
    fresh_input = (
        "TxID: Q901 | User: Quinn North | Card: 1029384756102938 | Amount: 12.50\n"
        "TxID: R802 | User: Riley West | Card: 5555444433332222 | Amount: 87.25\n"
        "TxID: Q901 | User: Ignored Duplicate | Card: 9999999999999999 | Amount: 999.00\n"
        "TxID: S703 | User: Sam East | Card: 1234567890123456 | Amount: 40.00\n"
        "TxID: T604 | User: Taylor South | Card: 8000000011117777 | Amount: 125.75\n"
    )

    try:
        with open(raw_data_path, "w") as f:
            f.write(fresh_input)
        if os.path.exists(report_path):
            os.remove(report_path)

        run_result = subprocess.run(
            ["cargo", "run", "--manifest-path", manifest_path, "--bin", binary_name],
            cwd=project_path,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert run_result.returncode == 0, f"The Rust application failed to compile or run:\n{run_result.stderr}"
        assert os.path.isfile(report_path), "Running the Rust application did not create /home/user/clean_report.txt."

        expected_output = expected_report(raw_data_path)
        with open(report_path, "r") as f:
            actual_output = f.read()
        assert actual_output.strip() == expected_output.strip(), (
            "The compiled Rust application did not correctly process a fresh input dataset."
        )
    finally:
        with open(raw_data_path, "wb") as f:
            f.write(original_raw)
        with open(report_path, "wb") as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
