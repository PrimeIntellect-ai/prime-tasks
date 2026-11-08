#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import json
import secrets
import shutil
import subprocess
import urllib.request
import pytest


def test_corruption_report():
    report_path = "/home/user/corruption_report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist."

    archive_dir = "/home/user/dataset_archive"
    expected_lines = []

    for root, _, files in os.walk(archive_dir):
        for f in files:
            if f.endswith('.log'):
                with open(os.path.join(root, f), 'r') as log_f:
                    for line in log_f:
                        if line.startswith("ERROR: CORRUPT_RECORD ID="):
                            m = re.search(r"ID=(\d+).*?\[(.*?)\]", line)
                            if m:
                                expected_lines.append((int(m.group(1)), m.group(1), m.group(2)))

    expected_lines.sort(key=lambda x: x[0])
    expected_text = "\n".join(f"{x[1]} - {x[2]}" for x in expected_lines)

    with open(report_path, 'r') as f:
        actual_text = f.read().strip()

    assert actual_text == expected_text, (
        f"Content of {report_path} is incorrect.\n"
        f"Expected:\n{expected_text}\n"
        f"Got:\n{actual_text}"
    )


def test_meta_files():
    script_path = "/home/user/generate_meta.py"
    assert os.path.exists(script_path), f"Python script {script_path} does not exist."

    archive_dir = "/home/user/dataset_archive"
    for root, _, files in os.walk(archive_dir):
        for f in files:
            if f.endswith('.dat'):
                dat_path = os.path.join(root, f)
                meta_path = dat_path[:-4] + ".meta"
                assert os.path.exists(meta_path), f"Missing meta file {meta_path} for {dat_path}."

                with open(dat_path, 'rb') as df:
                    expected_hex = df.read(8).hex()

                with open(meta_path, 'r') as mf:
                    actual_hex = mf.read().strip()

                assert actual_hex == expected_hex, (
                    f"Content of {meta_path} is incorrect. "
                    f"Expected {expected_hex}, got {actual_hex}."
                )


def test_final_summary():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"Bash script {script_path} does not exist."

    json_path = "/home/user/final_summary.json"
    assert os.path.exists(json_path), f"JSON summary file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert "corrupt_records" in data, "Missing key 'corrupt_records' in JSON."
    assert "new_meta_files" in data, "Missing key 'new_meta_files' in JSON."

    assert data["corrupt_records"] == 3, f"Expected 3 corrupt records, got {data['corrupt_records']}."
    assert data["new_meta_files"] == 3, f"Expected 3 new meta files, got {data['new_meta_files']}."


def test_server_running():
    pid_file = "/home/user/server.pid"
    assert os.path.exists(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, 'r') as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file does not contain a valid integer: '{pid_str}'."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from {pid_file}) is not running.")

    try:
        req = urllib.request.urlopen("http://localhost:8080/", timeout=2)
        assert req.status == 200, f"Server returned status {req.status} instead of 200."
        body = req.read().decode('utf-8')
        assert "exp_A" in body and "exp_B" in body, (
            "Server is reachable but does not seem to be serving the correct directory "
            "(/home/user/dataset_archive)."
        )
    except Exception as e:
        pytest.fail(f"Could not connect to HTTP server on port 8080 or verify content: {e}")


def test_zz_scripts_execute_and_compute_dynamic_results():
    generate_script = "/home/user/generate_meta.py"
    pipeline_script = "/home/user/pipeline.sh"
    report_path = "/home/user/corruption_report.txt"
    summary_path = "/home/user/final_summary.json"
    archive_dir = "/home/user/dataset_archive"

    for path in (generate_script, pipeline_script):
        assert os.path.isfile(path), f"{path} is not a regular file."
        assert os.path.getsize(path) > 0, f"{path} is empty."

    with open(report_path, "rb") as f:
        original_report = f.read()
    with open(summary_path, "rb") as f:
        original_summary = f.read()

    valid_meta = os.path.join(archive_dir, "exp_B/run_2/valid.meta")
    baseline_created = 0
    for root, _, files in os.walk(archive_dir):
        for name in files:
            if name.endswith(".dat"):
                meta = os.path.join(root, name[:-4] + ".meta")
                if os.path.exists(meta) and os.path.normpath(meta) != os.path.normpath(valid_meta):
                    baseline_created += 1

    token = secrets.token_hex(8)
    probe_dir = os.path.join(archive_dir, ".verifier_probe_" + token)
    probe_count = 2 + secrets.randbelow(4)
    extra_report_lines = 2 + secrets.randbelow(5)

    try:
        os.mkdir(probe_dir)

        expected_probe_meta = {}
        for i in range(probe_count):
            payload = secrets.token_bytes(8) + secrets.token_bytes(7)
            dat_path = os.path.join(probe_dir, f"novel_{token}_{i}.dat")
            meta_path = dat_path[:-4] + ".meta"
            with open(dat_path, "wb") as f:
                f.write(payload)
            expected_probe_meta[meta_path] = payload[:8].hex()

        existing_dat = os.path.join(probe_dir, f"existing_{token}.dat")
        existing_meta = existing_dat[:-4] + ".meta"
        sentinel = "do-not-overwrite-" + token
        with open(existing_dat, "wb") as f:
            f.write(secrets.token_bytes(16))
        with open(existing_meta, "w") as f:
            f.write(sentinel)

        subprocess.run(
            ["python3", generate_script],
            check=True,
            timeout=20,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        for meta_path, expected_hex in expected_probe_meta.items():
            assert os.path.isfile(meta_path), f"generate_meta.py did not create {meta_path}."
            with open(meta_path, "r") as f:
                actual = f.read().strip()
            assert actual == expected_hex, (
                f"generate_meta.py wrote incorrect probe metadata: expected "
                f"{expected_hex}, got {actual}."
            )

        with open(existing_meta, "r") as f:
            assert f.read() == sentinel, "generate_meta.py overwrote an existing .meta file."

        with open(report_path, "ab") as f:
            if original_report and not original_report.endswith(b"\n"):
                f.write(b"\n")
            for i in range(extra_report_lines):
                f.write(f"verifier-dynamic-line-{token}-{i}\n".encode())

        with open(report_path, "rb") as f:
            expected_report_count = len(f.read().splitlines())

        subprocess.run(
            ["bash", pipeline_script],
            check=True,
            timeout=20,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        with open(summary_path, "r") as f:
            try:
                dynamic_summary = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("pipeline.sh did not write valid JSON when executed.")

        assert "corrupt_records" in dynamic_summary, "Missing key 'corrupt_records' after running pipeline.sh."
        assert "new_meta_files" in dynamic_summary, "Missing key 'new_meta_files' after running pipeline.sh."
        assert dynamic_summary["corrupt_records"] == expected_report_count, (
            "pipeline.sh did not compute corrupt_records from the current report."
        )

        # A solution may track files created during the latest generator run, or all
        # metadata files created by the task across its runs. Both interpretations
        # must vary with these novel inputs and reject a fixed value of 3.
        acceptable_meta_counts = {probe_count, baseline_created + probe_count}
        assert dynamic_summary["new_meta_files"] in acceptable_meta_counts, (
            "pipeline.sh did not compute new_meta_files from generated metadata; "
            f"expected one of {sorted(acceptable_meta_counts)}, got "
            f"{dynamic_summary['new_meta_files']}."
        )
    finally:
        with open(report_path, "wb") as f:
            f.write(original_report)
        with open(summary_path, "wb") as f:
            f.write(original_summary)
        shutil.rmtree(probe_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
