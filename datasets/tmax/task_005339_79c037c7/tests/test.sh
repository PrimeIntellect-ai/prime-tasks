#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import subprocess
import tempfile
import urllib.error
import urllib.request

REPO = "/home/user/poly_parser"
JSON_PATH = "/home/user/diagnostics.json"
EXPECTED_TOKEN = "f9b23c4a-8d1e-4567-b90a-123456abcdef"


def load_diagnostics():
    assert os.path.isfile(JSON_PATH), f"File {JSON_PATH} does not exist."
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {JSON_PATH} is not valid JSON."


def test_diagnostics_json_exists_and_valid():
    data = load_diagnostics()
    assert "diagnostic_token" in data, "Key 'diagnostic_token' missing in diagnostics.json."
    assert "bad_commit" in data, "Key 'bad_commit' missing in diagnostics.json."
    assert "service_status" in data, "Key 'service_status' missing in diagnostics.json."


def test_diagnostic_token():
    data = load_diagnostics()
    assert data["diagnostic_token"] == EXPECTED_TOKEN, f"diagnostic_token is incorrect. Got {data['diagnostic_token']}."


def test_bad_commit():
    data = load_diagnostics()
    result = subprocess.run(
        ["git", "-C", REPO, "log", "--format=%H", "--grep=Optimize regex for faster parsing"],
        capture_output=True,
        text=True,
    )
    expected_hash = result.stdout.strip()
    assert expected_hash, "Could not find the bad commit in git history (test setup issue)."
    assert len(expected_hash) == 40
    assert data["bad_commit"] == expected_hash, f"bad_commit is incorrect. Expected {expected_hash}, got {data['bad_commit']}."


def test_service_status_json():
    data = load_diagnostics()
    assert data["service_status"] == "running", f"service_status should be 'running', got {data['service_status']}."


def test_diagnostic_server_running():
    try:
        response = urllib.request.urlopen("http://localhost:8080", timeout=2)
        assert response.status == 200, f"Diagnostic server returned status {response.status}."
        body = response.read().decode("utf-8")
        assert "Diagnostic server running" in body, "Diagnostic server is not returning the expected response."
    except urllib.error.URLError as e:
        assert False, f"Could not connect to the diagnostic server on port 8080: {e}"


def test_expected_server_process_is_running():
    found = False
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [part.decode("utf-8", "replace") for part in f.read().split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if "/home/user/poly_parser/diagnostic_server.py" not in args or "--token" not in args:
            continue
        token_index = args.index("--token") + 1
        if token_index < len(args) and args[token_index] == EXPECTED_TOKEN:
            found = True
            break
    assert found, "diagnostic_server.py is not running with the recovered token."


def test_evaluate_script_fixed():
    result = subprocess.run(
        ["python", "/home/user/poly_parser/evaluate.py", "--test", "/home/user/poly_parser/edge_case.txt"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"evaluate.py failed with error:\n{result.stderr}"
    assert "Parsed: 0.00015" in result.stdout, f"evaluate.py did not print the expected output. Got:\n{result.stdout}"


def test_evaluate_handles_generated_scientific_notation():
    evaluate_path = os.path.join(REPO, "evaluate.py")
    assert os.path.isfile(evaluate_path), "evaluate.py is missing."
    spec = importlib.util.spec_from_file_location("submitted_evaluate", evaluate_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "parse_coefficient", None)), "parse_coefficient is missing."

    rng = secrets.SystemRandom()
    literals = []
    for _ in range(12):
        sign = rng.choice(["", "+", "-"])
        whole = rng.randint(0, 999)
        fraction = rng.randint(1, 999999)
        marker = rng.choice(["e", "E"])
        exponent = rng.randint(-20, 20)
        exponent_sign = "+" if exponent >= 0 and rng.choice([True, False]) else ""
        literals.append(f"{sign}{whole}.{fraction:06d}{marker}{exponent_sign}{exponent}")

    for literal in literals:
        line = f"prefix COEFF({literal}) suffix"
        assert module.parse_coefficient(line) == float(literal), f"Failed to parse {literal}."

    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        temp_path = f.name
        for literal in literals:
            f.write(f"COEFF({literal})\n")
    try:
        result = subprocess.run(
            ["python", evaluate_path, "--test", temp_path],
            capture_output=True,
            text=True,
        )
    finally:
        os.unlink(temp_path)

    assert result.returncode == 0, f"evaluate.py failed generated cases:\n{result.stderr}"
    expected_lines = [f"Parsed: {float(literal)}" for literal in literals]
    assert result.stdout.strip().splitlines() == expected_lines, result.stdout


def test_fix_is_left_uncommitted():
    result = subprocess.run(
        ["git", "-C", REPO, "diff", "--quiet", "HEAD", "--", "evaluate.py"]
    )
    assert result.returncode == 1, "evaluate.py must contain an uncommitted fix."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
