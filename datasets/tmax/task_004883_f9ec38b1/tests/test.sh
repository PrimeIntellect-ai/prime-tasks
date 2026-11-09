#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import random
import stat
import subprocess

PROJECT_DIR = "/home/user/project"
RECOVERED_JSON_PATH = os.path.join(PROJECT_DIR, "recovered.json")
PARSE_CONFIG_PATH = os.path.join(PROJECT_DIR, "parse_config.py")
FUZZ_SH_PATH = os.path.join(PROJECT_DIR, "fuzz.sh")
FUZZ_RESULT_PATH = os.path.join(PROJECT_DIR, "fuzz_result.txt")
TEST_JSON_PATH = os.path.join(PROJECT_DIR, "test.json")

EXPECTED_RECOVERED = b'''[
  {"id": 1, "weight": 10},
  {"id": 2, "weight": "corrupted_value"},
  {"id": 3, "weight": 5}
]
'''


def run_parser(path):
    return subprocess.run(
        ["python3", PARSE_CONFIG_PATH, str(path)],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_recovered_json_content():
    assert os.path.isfile(RECOVERED_JSON_PATH), f"Recovered file not found at {RECOVERED_JSON_PATH}"

    expected_content = """[
  {"id": 1, "weight": 10},
  {"id": 2, "weight": "corrupted_value"},
  {"id": 3, "weight": 5}
]
"""
    with open(RECOVERED_JSON_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertion and additionally require exact bytes.
    assert content.strip() == expected_content.strip(), "Recovered JSON content does not match the original exactly."
    assert Path(RECOVERED_JSON_PATH).read_bytes() == EXPECTED_RECOVERED, "Recovered JSON bytes are not an exact match."


def test_parse_config_with_recovered_file():
    assert os.path.isfile(PARSE_CONFIG_PATH), f"Script not found at {PARSE_CONFIG_PATH}"

    result = run_parser(RECOVERED_JSON_PATH)

    assert result.returncode == 0, f"parse_config.py failed with exit code {result.returncode} on recovered.json"
    assert "Total weight: 15" in result.stdout, "parse_config.py did not output the correct total weight (15)."


def test_parse_config_handles_all_bad_weight_forms(tmp_path):
    # Values are selected at verification time so the expected total cannot be
    # satisfied by hard-coding the recovered example's answer.
    rng = random.SystemRandom()
    first = rng.randint(101, 100000)
    second = rng.randint(101, 100000)
    config = [
        {"id": 1, "weight": first},
        {"id": 2, "weight": str(rng.randint(1, 100000))},
        {"id": 3},
        {"id": 4, "weight": None},
        {"id": 5, "weight": {"bad": rng.randint(1, 1000)}},
        {"id": 6, "weight": [rng.randint(1, 1000)]},
        {"id": 7, "weight": True},
        {"id": 8, "weight": second},
    ]
    input_path = tmp_path / f"weights-{rng.getrandbits(64):016x}.json"
    input_path.write_text(json.dumps(config))

    result = run_parser(input_path)
    assert result.returncode == 0, result.stderr
    assert f"Total weight: {first + second}" in result.stdout, (
        "String, missing, or otherwise invalid weights were not all treated as 0."
    )


def test_parse_config_with_garbage_input(tmp_path):
    garbage_file = tmp_path / "garbage.json"
    garbage_file.write_bytes(os.urandom(50))

    result = run_parser(garbage_file)

    assert result.returncode == 0, f"parse_config.py did not exit gracefully (code 0) on garbage input. Exit code: {result.returncode}"
    assert "Invalid JSON" in result.stdout, "parse_config.py did not print 'Invalid JSON' when given garbage input."


def test_parse_config_with_deterministically_invalid_json(tmp_path):
    for index, payload in enumerate((b'{"unterminated":', b'not-json-at-all', b'[{]')):
        bad_file = tmp_path / f"invalid-{index}.json"
        bad_file.write_bytes(payload)
        result = run_parser(bad_file)
        assert result.returncode == 0, result.stderr
        assert "Invalid JSON" in result.stdout


def test_fuzz_script_properties_and_execution(tmp_path):
    assert os.path.isfile(FUZZ_SH_PATH), f"Fuzz script not found at {FUZZ_SH_PATH}"
    assert os.access(FUZZ_SH_PATH, os.X_OK), "Fuzz script is not executable."

    with open(FUZZ_SH_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "python3 parse_config.py" in content or "python parse_config.py" in content, "Fuzz script does not appear to invoke parse_config.py"
    assert "for" in content or "while" in content, "Fuzz script does not appear to contain a loop."
    assert "/dev/urandom" in content, "Fuzz script does not use /dev/urandom."
    assert "test.json" in content, "Fuzz script does not write/use test.json."

    # Temporarily instrument parse_config.py so every invocation proves that
    # test.json exists and contains exactly 50 bytes at call time.
    parser_path = Path(PARSE_CONFIG_PATH)
    original_bytes = parser_path.read_bytes()
    original_mode = stat.S_IMODE(parser_path.stat().st_mode)
    log_path = tmp_path / "fuzz-invocations.jsonl"
    wrapper = f'''import hashlib
import json
import pathlib
import sys

log = pathlib.Path({str(log_path)!r})
target = pathlib.Path({TEST_JSON_PATH!r})
record = {{"argc": len(sys.argv)}}
ok = False
try:
    supplied = pathlib.Path(sys.argv[1])
    data = supplied.read_bytes()
    record.update({{
        "path_ok": supplied.resolve() == target.resolve(),
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }})
    ok = record["path_ok"] and record["size"] == 50
except Exception as exc:
    record["error"] = type(exc).__name__
with log.open("a") as handle:
    handle.write(json.dumps(record) + "\\n")
sys.exit(0 if ok else 97)
'''

    try:
        parser_path.write_text(wrapper)
        os.chmod(parser_path, original_mode)
        instrumented = subprocess.run(
            ["bash", "-x", FUZZ_SH_PATH],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
    finally:
        parser_path.write_bytes(original_bytes)
        os.chmod(parser_path, original_mode)

    assert instrumented.returncode == 0, (
        f"fuzz.sh failed under instrumentation with code {instrumented.returncode}:\n"
        f"stdout:\n{instrumented.stdout}\nstderr:\n{instrumented.stderr}"
    )
    assert log_path.is_file(), "fuzz.sh never invoked parse_config.py."
    records = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
    assert len(records) == 10, f"fuzz.sh invoked parse_config.py {len(records)} times instead of exactly 10."
    assert all(r.get("path_ok") and r.get("size") == 50 for r in records), (
        "Every iteration must invoke the parser on a 50-byte test.json payload."
    )
    assert len({r["sha256"] for r in records}) == 10, "The ten generated payloads were not distinct."
    assert instrumented.stderr.count("/dev/urandom") >= 10, (
        "Execution trace did not show /dev/urandom being used in all ten iterations."
    )

    # Run the actual fuzzer with the submitted parser and require all ten real
    # garbage-input invocations to complete successfully.
    real_run = subprocess.run(
        [FUZZ_SH_PATH],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert real_run.returncode == 0, (
        f"fuzz.sh failed with the real parser (code {real_run.returncode}):\n"
        f"stdout:\n{real_run.stdout}\nstderr:\n{real_run.stderr}"
    )
    assert Path(TEST_JSON_PATH).is_file() and Path(TEST_JSON_PATH).stat().st_size == 50


def test_fuzz_result_file():
    assert os.path.isfile(FUZZ_RESULT_PATH), f"Fuzz result file not found at {FUZZ_RESULT_PATH}"

    with open(FUZZ_RESULT_PATH, "r") as f:
        content = f.read().strip()

    assert "SUCCESS" in content, "Fuzz result file does not contain 'SUCCESS'."
    assert content == "SUCCESS", "fuzz_result.txt must contain the word SUCCESS."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
