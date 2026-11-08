#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile

WORKSPACE = "/home/user/telemetry_diag"


def test_extracted_payloads():
    payloads_file = os.path.join(WORKSPACE, "extracted_payloads.txt")
    assert os.path.isfile(payloads_file), f"Missing {payloads_file}"

    with open(payloads_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_payloads = ["1A2B", "5F5F", "0000", "ABCD"]
    assert lines == expected_payloads, f"Extracted payloads do not match expected output. Got: {lines}"


def test_pipeline_functions():
    pipeline_path = os.path.join(WORKSPACE, "pipeline.py")
    assert os.path.isfile(pipeline_path), f"Missing {pipeline_path}"

    spec = importlib.util.spec_from_file_location("pipeline", pipeline_path)
    pipeline = importlib.util.module_from_spec(spec)
    sys.modules["pipeline"] = pipeline
    spec.loader.exec_module(pipeline)

    assert hasattr(pipeline, "decode_payload"), "Missing decode_payload function in pipeline.py"

    # Preserve the original fixed regression checks.
    test_cases_decode = {
        "1A2B": (int("1A2B", 16) ^ 0x5A5A) % 5000,
        "5F5F": (int("5F5F", 16) ^ 0x5A5A) % 5000,
        "0000": (int("0000", 16) ^ 0x5A5A) % 5000,
        "ABCD": (int("ABCD", 16) ^ 0x5A5A) % 5000,
        "FFFF": (int("FFFF", 16) ^ 0x5A5A) % 5000,
    }
    for hex_str, expected in test_cases_decode.items():
        result = pipeline.decode_payload(hex_str)
        assert result == expected, f"decode_payload('{hex_str}') returned {result}, expected {expected}"

    with open(pipeline_path, "r") as f:
        content = f.read()
        assert "subprocess" not in content or "subprocess.run" not in content, "decode_payload must be a pure Python implementation and not use subprocess"

    # Also reject direct subprocess imports, including aliased imports that evade
    # the original textual check.
    tree = ast.parse(content, filename=pipeline_path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert all(alias.name != "subprocess" for alias in node.names), "pipeline.py must not import subprocess"
        elif isinstance(node, ast.ImportFrom):
            assert node.module != "subprocess", "pipeline.py must not import from subprocess"

    assert hasattr(pipeline, "calculate_temperature"), "Missing calculate_temperature function in pipeline.py"

    test_cases_temp = [0, 100, 255, 1234, 4999]
    for val in test_cases_temp:
        expected = round((val / 10.0) * 1.8 + 32.0, 2)
        result = pipeline.calculate_temperature(val)
        assert result == expected, f"calculate_temperature({val}) returned {result}, expected {expected}"

    # Exercise both implementations on unpredictable inputs so fixed lookup
    # tables cannot satisfy the verifier. Temporarily make the supplied binary
    # unavailable and block common process-launch APIs during these calls.
    rng = secrets.SystemRandom()
    decode_inputs = set()
    while len(decode_inputs) < 128:
        width = rng.randrange(1, 9)
        value = rng.randrange(0, 16 ** width)
        text = f"{value:0{width}X}"
        if rng.randrange(2):
            text = text.lower()
        decode_inputs.add(text)

    temp_inputs = {rng.randrange(-100000, 100001) for _ in range(128)}
    temp_inputs.update({-1, 1, 10, 101, 5000, 100000})

    decoder_path = os.path.join(WORKSPACE, "legacy_decoder")
    hidden_decoder = os.path.join(
        tempfile.gettempdir(), f"legacy_decoder.hidden.{os.getpid()}.{secrets.token_hex(8)}"
    )
    moved_decoder = os.path.exists(decoder_path)

    old_run = subprocess.run
    old_popen = subprocess.Popen
    old_check_output = subprocess.check_output
    old_check_call = subprocess.check_call
    old_call = subprocess.call
    old_system = os.system
    old_os_popen = os.popen

    def blocked(*args, **kwargs):
        raise AssertionError("decode_payload must not launch an external process")

    try:
        if moved_decoder:
            os.replace(decoder_path, hidden_decoder)
        subprocess.run = blocked
        subprocess.Popen = blocked
        subprocess.check_output = blocked
        subprocess.check_call = blocked
        subprocess.call = blocked
        os.system = blocked
        os.popen = blocked

        for hex_str in decode_inputs:
            expected = (int(hex_str, 16) ^ 0x5A5A) % 5000
            result = pipeline.decode_payload(hex_str)
            assert result == expected, f"decode_payload('{hex_str}') returned {result}, expected {expected}"
            assert isinstance(result, int) and not isinstance(result, bool)

        for val in temp_inputs:
            expected = round((val / 10.0) * 1.8 + 32.0, 2)
            result = pipeline.calculate_temperature(val)
            assert result == expected, f"calculate_temperature({val}) returned {result}, expected {expected}"
            assert isinstance(result, float), "calculate_temperature must return a float"
    finally:
        subprocess.run = old_run
        subprocess.Popen = old_popen
        subprocess.check_output = old_check_output
        subprocess.check_call = old_check_call
        subprocess.call = old_call
        os.system = old_system
        os.popen = old_os_popen
        if moved_decoder and os.path.exists(hidden_decoder):
            os.replace(hidden_decoder, decoder_path)


def test_student_pytest_suite():
    test_file = os.path.join(WORKSPACE, "test_pipeline.py")
    assert os.path.isfile(test_file), f"Missing student test file {test_file}"

    # Preserve the original execution and source-level assertion.
    result = subprocess.run(["pytest", test_file], capture_output=True, text=True)
    assert result.returncode == 0, f"Student's pytest suite failed:\n{result.stdout}\n{result.stderr}"

    with open(test_file, "r") as f:
        content = f.read()
        test_count = content.count("def test_")
        assert test_count >= 1, "Student test file must contain at least one test function (preferably parameterized or multiple test functions)"

    # Require at least four actually collected pytest cases, including
    # parameterized cases rather than merely counting function definitions.
    collected = subprocess.run(
        ["pytest", "--collect-only", "-q", test_file],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
    )
    assert collected.returncode == 0, f"Could not collect student tests:\n{collected.stdout}\n{collected.stderr}"
    node_ids = [line.strip() for line in collected.stdout.splitlines() if "::" in line]
    assert len(node_ids) >= 4, f"Student suite must collect at least 4 test cases; collected {len(node_ids)}"

    # Run the suite against an instrumented correct implementation to establish
    # that it exercises at least four distinct payload-to-temperature paths.
    runner = os.path.join(tempfile.gettempdir(), f"telemetry_test_runner_{os.getpid()}.py")
    runner_source = r'''import json
import os
import sys
import types
import pytest

events = {"decode": [], "temperature": []}
target = os.environ.get("MUTATE_RAW")
target = None if target is None else int(target)

pipeline = types.ModuleType("pipeline")
pipeline.__file__ = os.path.join(os.environ["WORKSPACE"], "pipeline.py")

def decode_payload(hex_str: str) -> int:
    result = (int(hex_str, 16) ^ 0x5A5A) % 5000
    events["decode"].append([hex_str, result])
    return result

def calculate_temperature(raw_val: int) -> float:
    events["temperature"].append(raw_val)
    result = round((raw_val / 10.0) * 1.8 + 32.0, 2)
    if target is not None and raw_val == target:
        return result + 10000.0
    return result

pipeline.decode_payload = decode_payload
pipeline.calculate_temperature = calculate_temperature
sys.modules["pipeline"] = pipeline
rc = pytest.main(["-q", os.environ["TEST_FILE"]])
with open(os.environ["EVENT_LOG"], "w") as f:
    json.dump({"returncode": rc, "events": events}, f)
'''
    with open(runner, "w") as f:
        f.write(runner_source)

    try:
        log_path = os.path.join(tempfile.gettempdir(), f"telemetry_events_{os.getpid()}.json")
        env = os.environ.copy()
        env.update({"WORKSPACE": WORKSPACE, "TEST_FILE": test_file, "EVENT_LOG": log_path})
        proxy_run = subprocess.run([sys.executable, runner], cwd=WORKSPACE, env=env, capture_output=True, text=True)
        assert proxy_run.returncode == 0 and os.path.isfile(log_path), proxy_run.stdout + proxy_run.stderr
        with open(log_path) as f:
            report = json.load(f)
        assert report["returncode"] == 0, "Student tests do not pass against a correct instrumented implementation"

        decoded = report["events"]["decode"]
        temp_raws = set(report["events"]["temperature"])
        pairs = {}
        for payload, raw in decoded:
            assert isinstance(payload, str) and re.fullmatch(r"[0-9A-Fa-f]+", payload), "Regression payloads must be hexadecimal strings"
            pairs[payload] = raw

        assert len(pairs) >= 4, "Student suite must test at least 4 distinct payload strings"
        distinct_raws = []
        for raw in pairs.values():
            if raw in temp_raws and raw not in distinct_raws:
                distinct_raws.append(raw)
        assert len(distinct_raws) >= 4, "At least 4 payloads must be decoded and passed to calculate_temperature"

        # Mutate each of four observed final temperatures independently. A real
        # regression expectation must make every such run fail.
        for index, raw in enumerate(distinct_raws[:4]):
            mutant_log = log_path + f".mutant{index}"
            mutant_env = env.copy()
            mutant_env["EVENT_LOG"] = mutant_log
            mutant_env["MUTATE_RAW"] = str(raw)
            mutant_run = subprocess.run([sys.executable, runner], cwd=WORKSPACE, env=mutant_env, capture_output=True, text=True)
            assert mutant_run.returncode == 0 and os.path.isfile(mutant_log), mutant_run.stdout + mutant_run.stderr
            with open(mutant_log) as f:
                mutant_report = json.load(f)
            assert mutant_report["returncode"] != 0, (
                f"Student suite did not detect an incorrect final temperature for decoded raw value {raw}"
            )
    finally:
        for path in [runner] + [
            os.path.join(tempfile.gettempdir(), f"telemetry_events_{os.getpid()}.json")
        ] + [
            os.path.join(tempfile.gettempdir(), f"telemetry_events_{os.getpid()}.json.mutant{i}") for i in range(4)
        ]:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
