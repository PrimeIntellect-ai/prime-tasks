#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import json
import os
import random
import re
import secrets
import subprocess
import tempfile


def test_yq_installed():
    """Verify the repaired, installed yq package is real and functional."""
    yq_path = "/home/user/.local/bin/yq"
    assert os.path.isfile(yq_path), f"{yq_path} not found. Did you install yq locally?"
    assert os.access(yq_path, os.X_OK), f"{yq_path} is not executable."

    result = subprocess.run([yq_path, "--version"], capture_output=True, text=True)
    assert "yq 3.2.3" in result.stdout or "yq 3.2.3" in result.stderr, f"Expected yq 3.2.3, got {result.stdout.strip()} {result.stderr.strip()}"

    setup_path = "/app/yq-3.2.3/setup.py"
    with open(setup_path, "r") as f:
        ast.parse(f.read(), filename=setup_path)

    probe = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", "-c",
         "import importlib.metadata, yq; print(importlib.metadata.version('yq')); print(yq.__file__)"],
        capture_output=True, text=True
    )
    assert probe.returncode == 0, f"Installed yq package cannot be imported by user:\n{probe.stderr}"
    assert probe.stdout.splitlines()[0].strip() == "3.2.3", probe.stdout

    marker = secrets.token_hex(8)
    yaml_input = f"job:\n  name: {marker}\n  count: 17\n  enabled: true\n"
    functional = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", yq_path, "."],
        input=yaml_input, capture_output=True, text=True
    )
    assert functional.returncode == 0, f"yq failed to parse YAML:\n{functional.stderr}"
    assert json.loads(functional.stdout) == {
        "job": {"name": marker, "count": 17, "enabled": True}
    }, f"Unexpected yq conversion output: {functional.stdout!r}"


def test_pipeline_script_exists():
    """Verify pipeline.sh exists and is executable."""
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} not found."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_cron_job_configured():
    """Verify the cron job is configured correctly."""
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab. Is it configured?"

    expected_cron = "*/15 * * * * /home/user/pipeline.sh /app/incoming_logs /home/user/processed_logs"
    assert expected_cron in result.stdout, f"Crontab does not contain the expected entry. Found:\n{result.stdout}"


def get_json_lines(file_path):
    if not os.path.isfile(file_path):
        return []
    with open(file_path, "r") as f:
        lines = f.read().splitlines()
    res = []
    for line in lines:
        if line.strip():
            try:
                res.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return res


def test_adversarial_corpus_evil():
    """Verify that all evil logs are rejected."""
    script_path = "/home/user/pipeline.sh"
    evil_in = "/app/corpora/evil"
    evil_out = "/tmp/evil_out"

    os.makedirs(evil_out, exist_ok=True)
    result = subprocess.run([script_path, evil_in, evil_out], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed on evil corpus:\n{result.stderr}"

    out_file = os.path.join(evil_out, "cleaned.json")
    lines = get_json_lines(out_file)
    assert len(lines) == 0, f"Evil logs bypassed the filter. Found {len(lines)} logs in output."


def test_adversarial_corpus_clean():
    """Verify that all clean logs are preserved and deduplicated."""
    script_path = "/home/user/pipeline.sh"
    clean_in = "/app/corpora/clean"
    clean_out = "/tmp/clean_out"

    os.makedirs(clean_out, exist_ok=True)
    result = subprocess.run([script_path, clean_in, clean_out], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed on clean corpus:\n{result.stderr}"

    out_file = os.path.join(clean_out, "cleaned.json")
    assert os.path.isfile(out_file), f"Output file {out_file} not created."

    output_lines = get_json_lines(out_file)

    expected = []
    seen_ids = set()
    for root, _, files in os.walk(clean_in):
        for file in sorted(files):
            if file.endswith(".json"):
                lines = get_json_lines(os.path.join(root, file))
                for obj in lines:
                    req_id = obj.get("request_id")
                    if req_id not in seen_ids:
                        seen_ids.add(req_id)
                        expected.append(obj)

    assert len(output_lines) == len(expected), f"Clean logs modified or dropped. Expected {len(expected)}, got {len(output_lines)}."
    for out_obj, exp_obj in zip(output_lines, expected):
        assert out_obj == exp_obj, f"Output log {out_obj} does not match expected {exp_obj}."


def is_valid(obj):
    if not isinstance(obj, dict):
        return False
    duration = obj.get("duration_ms")
    operation = obj.get("operation")
    status = obj.get("status")
    return (
        isinstance(duration, (int, float))
        and not isinstance(duration, bool)
        and duration >= 0
        and isinstance(operation, str)
        and re.fullmatch(r"[a-zA-Z0-9_]+", operation) is not None
        and isinstance(status, str)
        and status in ("success", "failure")
    )


def test_pipeline_dynamic_corpus_and_deduplication():
    """Exercise all rules on unpredictable files, values, and duplicates."""
    script_path = "/home/user/pipeline.sh"
    token = secrets.token_hex(10)
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))

    with tempfile.TemporaryDirectory(prefix="pipeline_input_") as input_dir, tempfile.TemporaryDirectory(prefix="pipeline_output_") as output_dir:
        records = {"10_first.json": [], "20_middle.json": [], "90_last.json": []}
        ids = [f"{token}_{i}" for i in range(16)]

        for i in range(48):
            obj = {
                "request_id": rng.choice(ids),
                "operation": f"calc_{token}_{i}",
                "duration_ms": rng.choice([0, i, i + 0.25]),
                "status": rng.choice(["success", "failure"]),
                "payload": {"nonce": secrets.token_hex(5), "index": i},
            }
            defect = i % 8
            if defect == 1:
                obj["duration_ms"] = -rng.randint(1, 100)
            elif defect == 2:
                obj["duration_ms"] = True
            elif defect == 3:
                obj.pop("duration_ms")
            elif defect == 4:
                obj["operation"] = f"bad;{token}"
            elif defect == 5:
                obj["operation"] = ""
            elif defect == 6:
                obj["status"] = "pending"
            elif defect == 7:
                obj["status"] = 1
            records[rng.choice(list(records))].append(json.dumps(obj, separators=(",", ":")))

        missing_id = {
            "operation": f"no_id_{token}", "duration_ms": 0, "status": "success",
            "payload": secrets.token_hex(4)
        }
        records["10_first.json"].insert(0, json.dumps(missing_id))
        records["90_last.json"].append(json.dumps(dict(missing_id, payload="later_duplicate")))
        records["20_middle.json"].insert(1, "{this is malformed JSON")
        records["20_middle.json"].append(json.dumps(["not", "an", "object"]))

        ignored = {
            "request_id": f"ignored_{token}", "operation": "valid_but_ignored",
            "duration_ms": 1, "status": "success"
        }
        with open(os.path.join(input_dir, "00_ignore.txt"), "w") as f:
            f.write(json.dumps(ignored) + "\n")

        for filename, lines in records.items():
            with open(os.path.join(input_dir, filename), "w") as f:
                f.write("\n".join(lines) + "\n")

        expected = []
        seen = []
        for filename in sorted(records):
            for line in records[filename]:
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not is_valid(obj):
                    continue
                request_id = obj.get("request_id")
                if request_id not in seen:
                    seen.append(request_id)
                    expected.append(obj)

        result = subprocess.run([script_path, input_dir, output_dir], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Pipeline failed on generated corpus:\n{result.stderr}"
        out_file = os.path.join(output_dir, "cleaned.json")
        assert os.path.isfile(out_file), "Pipeline did not create cleaned.json"

        actual = []
        with open(out_file, "r") as f:
            for line_number, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    actual.append(json.loads(line))
                except json.JSONDecodeError as exc:
                    raise AssertionError(f"Output line {line_number} is not valid JSON: {line!r}") from exc

        assert actual == expected, f"Generated corpus mismatch.\nExpected: {expected!r}\nActual: {actual!r}"
        assert ignored not in actual, "A non-.json input file was processed"


def test_pipeline_requires_exactly_two_arguments():
    script_path = "/home/user/pipeline.sh"
    for args in ([], ["/tmp"], ["/tmp", "/tmp", "extra"]):
        result = subprocess.run([script_path, *args], capture_output=True, text=True, timeout=10)
        assert result.returncode != 0, f"Pipeline accepted {len(args)} arguments instead of exactly two"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
