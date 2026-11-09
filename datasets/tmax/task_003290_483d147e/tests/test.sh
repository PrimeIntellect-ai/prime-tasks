#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import string
import subprocess
import sys
import tempfile
from collections import defaultdict, deque

SCRIPT_PATH = "/home/user/process_configs.py"
CALCULATOR_PATH = "/app/vendored/py-rolling-stats-0.1.0/py_rolling_stats/calculator.py"


def test_calculator_fixed():
    assert os.path.isfile(CALCULATOR_PATH), f"calculator.py is missing: {CALCULATOR_PATH}"
    with open(CALCULATOR_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "MAX_WINDOW_SIZE" in content, "The typo 'MAX_WINDW_SIZE' was not fixed to 'MAX_WINDOW_SIZE'."
    assert "MAX_WINDW_SIZE" not in content, "The typo 'MAX_WINDW_SIZE' is still present in calculator.py."

    code = r'''
import json
from importlib.metadata import version
from py_rolling_stats import RollingCalculator
c = RollingCalculator()
for value in [100, 100, 100, 0, 0]:
    c.add(value)
print(json.dumps({"version": version("py-rolling-stats"), "window": c.window_size, "average": c.average()}))
'''
    env = os.environ.copy()
    env["MAX_WINDOW_SIZE"] = "5"
    env["MAX_WINDW_SIZE"] = "2"
    result = subprocess.run(
        [sys.executable, "-I", "-c", code],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Installed package could not be imported or used:\n{result.stderr}"
    data = json.loads(result.stdout.strip())
    assert data["version"] == "0.1.0", "The vendored distribution is not installed."
    assert data["window"] == 5, "RollingCalculator does not read MAX_WINDOW_SIZE correctly."
    assert data["average"] == 60.0, "Installed RollingCalculator does not calculate a five-item rolling average."


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Processor script missing at {SCRIPT_PATH}"


def mask_content(text):
    text = re.sub(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', '[IPV4]', text)
    text = re.sub(r'\bAKIA[A-Z0-9]{16}\b', '[AWS_KEY]', text)
    text = re.sub(r'password=\S+', 'password=[PASSWORD]', text)
    text = re.sub(r'"password"\s*:\s*"[^"]*"', '"password": "[PASSWORD]"', text)
    return text


class ExpectedRollingStats:
    def __init__(self):
        self.history = defaultdict(lambda: deque(maxlen=5))

    def add_and_check(self, server_id, diff_size):
        self.history[server_id].append(diff_size)
        return sum(self.history[server_id]) / len(self.history[server_id]) > 50.0


def run_student_script(input_dir, output_dir, max_window="5", extra_env=None):
    env = os.environ.copy()
    if max_window is None:
        env.pop("MAX_WINDOW_SIZE", None)
    else:
        env["MAX_WINDOW_SIZE"] = max_window
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, input_dir, output_dir],
        capture_output=True,
        text=True,
        env=env,
        cwd="/tmp",
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def verify_corpus(corpus_path, max_window="5", require_clean=False):
    with tempfile.TemporaryDirectory() as temp_out:
        run_student_script(corpus_path, temp_out, max_window=max_window)

        input_files = sorted(
            name for name in os.listdir(corpus_path)
            if name.endswith(".jsonl") and os.path.isfile(os.path.join(corpus_path, name))
        )
        output_entries = sorted(os.listdir(temp_out))
        assert input_files == output_entries, "Output files do not exactly match input JSONL files."

        stats = ExpectedRollingStats()
        for fname in input_files:
            with open(os.path.join(corpus_path, fname), encoding="utf-8") as fin:
                input_lines = fin.read().splitlines()
            with open(os.path.join(temp_out, fname), encoding="utf-8") as fout:
                output_lines = fout.read().splitlines()

            assert len(input_lines) == len(output_lines), f"Line count changed in {fname}."
            for line_idx, (in_line, out_line) in enumerate(zip(input_lines, output_lines), 1):
                if not in_line.strip():
                    continue
                in_obj = json.loads(in_line)
                out_obj = json.loads(out_line)
                expected = dict(in_obj)
                expected["content"] = mask_content(in_obj.get("content", ""))
                expected["anomaly"] = stats.add_and_check(
                    in_obj.get("server_id"), in_obj.get("diff_size", 0)
                )

                assert isinstance(out_obj.get("anomaly"), bool), (
                    f"anomaly must be a JSON boolean in {fname}:{line_idx}"
                )
                assert out_obj == expected, (
                    f"Incorrect or non-preserving output in {fname}:{line_idx}.\n"
                    f"Expected: {expected!r}\nActual: {out_obj!r}"
                )
                if require_clean:
                    assert out_obj["content"] == in_obj["content"], (
                        f"Clean content was modified in {fname}:{line_idx}"
                    )


def test_existing_clean_corpus():
    path = "/home/user/corpora/clean"
    if os.path.isdir(path):
        verify_corpus(path, require_clean=True)


def test_existing_evil_corpus():
    path = "/home/user/corpora/evil"
    if os.path.isdir(path):
        verify_corpus(path)


def random_token(length=12):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def test_randomized_general_pipeline_and_field_preservation():
    nonce = random_token()
    server_a = "rolling-" + random_token()
    server_b = "separate-" + random_token()
    server_c = "strict-" + random_token()
    aws_key = "AKIA" + ''.join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(16))
    ip = f"{secrets.randbelow(200)+1}.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(254)+1}"
    password = random_token(18)

    rows = [
        {"timestamp": nonce + "-01", "server_id": server_a, "diff_size": 100, "content": "plain=" + nonce, "owner": "ops", "metadata": {"n": 1}},
        {"timestamp": nonce + "-02", "server_id": server_b, "diff_size": 1, "content": f"endpoint={ip}", "owner": "security", "tags": [nonce, 2]},
        {"timestamp": nonce + "-03", "server_id": server_a, "diff_size": 100, "content": f"access={aws_key}", "enabled": True},
        {"timestamp": nonce + "-04", "server_id": server_a, "diff_size": 100, "content": f"password={password}\nkeep=yes", "nullable": None},
        {"timestamp": nonce + "-05", "server_id": server_c, "diff_size": 49, "content": "unchanged strict content", "extra_number": 7.25},
        {"timestamp": nonce + "-06", "server_id": server_a, "diff_size": 0, "content": f'payload={{"password": "value {password}"}}', "nested": {"keep": [1, 2, 3]}},
        {"timestamp": nonce + "-07", "server_id": server_c, "diff_size": 51, "content": "average is exactly fifty", "note": nonce},
        {"timestamp": nonce + "-08", "server_id": server_a, "diff_size": 0, "content": f"ip={ip} key={aws_key} password={password}", "final": "preserve-me"},
        {"timestamp": nonce + "-09", "server_id": server_a, "diff_size": 0, "content": "window eviction check", "array": [False, nonce]},
    ]

    clean_rows = [
        {"timestamp": nonce + "-clean", "server_id": "clean-" + random_token(), "diff_size": 10, "content": "host=localhost\nuser=" + nonce, "custom": {"preserved": True}}
    ]

    with tempfile.TemporaryDirectory() as input_dir:
        first_name = f"events_{random_token()}.jsonl"
        second_name = f"unchanged_{random_token()}.jsonl"
        with open(os.path.join(input_dir, first_name), "w", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row) + "\n")
        with open(os.path.join(input_dir, second_name), "w", encoding="utf-8") as f:
            for row in clean_rows:
                f.write(json.dumps(row) + "\n")

        # A hostile inherited value catches processors that fail to set the required value to 5.
        verify_corpus(input_dir, max_window="2")


def test_processor_actually_uses_rolling_calculator():
    nonce = random_token()
    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, "input_" + random_token())
        output_dir = os.path.join(root, "output_" + random_token())
        stub_dir = os.path.join(root, "stub")
        package_dir = os.path.join(stub_dir, "py_rolling_stats")
        os.makedirs(input_dir)
        os.makedirs(package_dir)
        log_path = os.path.join(root, "rolling_calls.jsonl")
        filename = "probe_" + random_token() + ".jsonl"
        row = {
            "timestamp": nonce,
            "server_id": "probe-" + random_token(),
            "diff_size": 1,
            "content": "safe=" + nonce,
            "preserve": [1, 2, 3],
        }
        with open(os.path.join(input_dir, filename), "w", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")

        stub = r'''import json
import os

LOG = os.environ["ROLLING_PROBE_LOG"]

def _write(event, **values):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps({"event": event, **values}) + "\\n")

class RollingCalculator:
    def __init__(self):
        _write("init", max_window=os.environ.get("MAX_WINDOW_SIZE"))
    def add(self, value):
        _write("add", value=value)
    def average(self):
        _write("average")
        return 99.0
'''
        with open(os.path.join(package_dir, "__init__.py"), "w", encoding="utf-8") as f:
            f.write(stub)
        with open(os.path.join(package_dir, "calculator.py"), "w", encoding="utf-8") as f:
            f.write("from . import RollingCalculator\n")

        env = {
            "PYTHONPATH": stub_dir + os.pathsep + os.environ.get("PYTHONPATH", ""),
            "ROLLING_PROBE_LOG": log_path,
        }
        run_student_script(input_dir, output_dir, max_window="2", extra_env=env)

        with open(os.path.join(output_dir, filename), encoding="utf-8") as f:
            output = json.loads(f.readline())
        assert output.get("anomaly") is True, (
            "Processor output does not use RollingCalculator.average(); the probe returned 99.0."
        )
        expected = dict(row)
        expected["anomaly"] = True
        assert output == expected, "Processor failed to preserve fields during RollingCalculator probe."

        assert os.path.isfile(log_path), "RollingCalculator was not instantiated."
        with open(log_path, encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        events = [entry["event"] for entry in calls]
        assert "init" in events and "add" in events and "average" in events, (
            "Processor must instantiate RollingCalculator and call add() and average()."
        )
        init_calls = [entry for entry in calls if entry["event"] == "init"]
        assert all(entry.get("max_window") == "5" for entry in init_calls), (
            "Processor must set MAX_WINDOW_SIZE to 5 before constructing RollingCalculator."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
