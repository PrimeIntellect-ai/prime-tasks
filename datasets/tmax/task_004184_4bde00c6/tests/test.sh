#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import itertools
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import uuid

WORKSPACE_DIR = "/home/user/workspace"
MINIMAL_CRASH_PATH = os.path.join(WORKSPACE_DIR, "minimal_crash.txt")
BEACON_PARSER_PATH = os.path.join(WORKSPACE_DIR, "beacon_parser.py")
TEST_PARSER_PATH = os.path.join(WORKSPACE_DIR, "test_parser.py")
CRASH_PAYLOAD_PATH = os.path.join(WORKSPACE_DIR, "crash_payload.txt")


def vulnerable_parse(payload):
    segments = payload.split(',')
    weights = []
    padding = []
    for seg in segments:
        if seg.replace('.', '', 1).isdigit():
            weights.append(float(seg))
        elif seg.startswith('PAD'):
            padding.append(seg)
        else:
            if seg[0] == 'X':
                pass
    if not weights:
        return True
    total_weight = sum(weights)
    expected = len(weights) * 0.1
    if total_weight != expected:
        raise ValueError(f"Checksum precision mismatch: {total_weight} != {expected}")
    return True


def exception_signature(payload):
    try:
        vulnerable_parse(payload)
    except Exception as exc:
        return type(exc), str(exc)
    return None


def is_subsequence(needle, haystack):
    pos = 0
    for component in haystack:
        if pos < len(needle) and needle[pos] == component:
            pos += 1
    return pos == len(needle)


def run_cli(payload):
    return subprocess.run(
        ["python3", BEACON_PARSER_PATH, "--payload", payload],
        capture_output=True,
        text=True,
        timeout=10,
    )


def load_parser():
    name = "submitted_beacon_parser_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, BEACON_PARSER_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_submitted_tests():
    collect = subprocess.run(
        ["python3", "-m", "pytest", "--collect-only", "-q", TEST_PARSER_PATH],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    output = collect.stdout + "\n" + collect.stderr
    assert collect.returncode == 0, f"pytest could not collect the submitted tests:\n{output}"
    counts = [int(x) for x in re.findall(r"(\d+) tests? collected", output)]
    if not counts:
        counts = [len(re.findall(r"::test[^\s]*", output))]
    assert max(counts or [0]) >= 3, "test_parser.py must contain at least three collected regression tests"

    return subprocess.run(
        ["python3", "-m", "pytest", "-q", TEST_PARSER_PATH],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )


def mutant_source(float_bug=False, empty_bug=False, fail_payload=None):
    return textwrap.dedent(f'''\
        import argparse
        import math
        import sys

        FAIL_PAYLOAD = {fail_payload!r}

        def parse_payload(payload):
            if FAIL_PAYLOAD is not None and payload == FAIL_PAYLOAD:
                raise IndexError("Malformed padding sequence")
            segments = payload.split(',')
            weights = []
            padding = []
            for seg in segments:
                if seg.replace('.', '', 1).isdigit():
                    weights.append(float(seg))
                elif seg.startswith('PAD'):
                    padding.append(seg)
                elif not seg:
                    if {empty_bug!r}:
                        _ = seg[0]
                    continue
                elif seg[0] == 'X':
                    pass
            if not weights:
                return True
            total_weight = sum(weights)
            expected = len(weights) * 0.1
            mismatch = (total_weight != expected) if {float_bug!r} else (not math.isclose(total_weight, expected, rel_tol=1e-9, abs_tol=1e-12))
            if mismatch:
                raise ValueError(f"Checksum precision mismatch: {{total_weight}} != {{expected}}")
            return True

        if __name__ == "__main__":
            parser = argparse.ArgumentParser()
            parser.add_argument("--payload", required=True)
            args = parser.parse_args()
            try:
                parse_payload(args.payload)
                print("Payload processed successfully.")
            except Exception as exc:
                print(f"Error: {{exc}}", file=sys.stderr)
                sys.exit(1)
    ''')


def suite_result_with_parser(source):
    with open(BEACON_PARSER_PATH, "w") as f:
        f.write(source)
    shutil.rmtree(os.path.join(WORKSPACE_DIR, "__pycache__"), ignore_errors=True)
    return subprocess.run(
        ["python3", "-m", "pytest", "-q", TEST_PARSER_PATH],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )


def test_minimal_crash_exists_and_is_truly_minimal():
    assert os.path.isfile(MINIMAL_CRASH_PATH), f"The file {MINIMAL_CRASH_PATH} is missing. Delta debugging was not saved correctly."
    with open(MINIMAL_CRASH_PATH, 'r') as f:
        content = f.read().strip()
    assert len(content) > 0, f"The file {MINIMAL_CRASH_PATH} is empty."

    with open(CRASH_PAYLOAD_PATH, 'r') as f:
        original = f.read().strip()
    original_components = original.split(',')
    candidate_components = content.split(',')
    target = exception_signature(original)
    assert target is not None and target[0] in (ValueError, IndexError)
    assert exception_signature(content) == target, (
        "minimal_crash.txt does not reproduce the same exception type and message "
        "as the supplied crashing payload against the original parser"
    )
    assert is_subsequence(candidate_components, original_components), (
        "minimal_crash.txt must be formed by removing comma-separated components "
        "from crash_payload.txt"
    )

    minimum = None
    for size in range(1, len(original_components) + 1):
        found = False
        for indices in itertools.combinations(range(len(original_components)), size):
            payload = ','.join(original_components[i] for i in indices)
            if payload and exception_signature(payload) == target:
                found = True
                break
        if found:
            minimum = size
            break
    assert minimum is not None
    assert len(candidate_components) == minimum, (
        f"minimal_crash.txt has {len(candidate_components)} components, but a "
        f"{minimum}-component reproducer exists"
    )


def test_delta_debugging_script_exists():
    candidates = []
    for root, dirs, files in os.walk(WORKSPACE_DIR):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for filename in files:
            path = os.path.join(root, filename)
            if path in (BEACON_PARSER_PATH, TEST_PARSER_PATH):
                continue
            if not filename.endswith((".py", ".sh")):
                continue
            try:
                source = open(path, encoding="utf-8").read()
            except (OSError, UnicodeError):
                continue
            lower = source.lower()
            if ("crash_payload" in lower and "minimal_crash" in lower and
                    any(term in lower for term in ("ddmin", "delta", "minimiz"))):
                candidates.append((path, source))
    assert candidates, "No delta-debugging script that reads the crash payload and writes the minimized payload was found"
    assert any(any(token in source for token in ("for ", "while ", "combinations", "ddmin")) for _, source in candidates), (
        "The delta-debugging script does not appear to implement a reduction loop"
    )


def test_beacon_parser_fixed_and_generalized():
    assert os.path.isfile(BEACON_PARSER_PATH), f"The file {BEACON_PARSER_PATH} is missing."

    test_payload = "0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,PAD,"
    result = run_cli(test_payload)
    assert result.returncode == 0, (
        f"beacon_parser.py failed to process the payload '{test_payload}'.\n"
        f"Standard Error: {result.stderr}\n"
        "Ensure both the floating-point precision bug and the empty segment/trailing comma bug are fixed."
    )

    module = load_parser()
    assert callable(getattr(module, "parse_payload", None)), "beacon_parser.py must retain parse_payload(payload)"

    random_tag = uuid.uuid4().hex[:10]
    valid_payloads = []
    for count in (3, 7, 10, 19, 31):
        fields = ["0.1"] * count
        fields.insert(1, "")
        fields.extend(["", "PAD" + random_tag, ""])
        valid_payloads.append(','.join(fields))
    valid_payloads.extend(["", ",", f",PAD{random_tag},,", "Xtoken,,PAD,"])

    for payload in valid_payloads:
        assert module.parse_payload(payload) is True, f"parse_payload failed valid edge-case payload {payload!r}"

    for count in (4, 11, 23):
        fields = ["0.1"] * count
        fields[count // 2] = "0.2"
        payload = ','.join(fields + ["", "PAD" + random_tag, ""])
        try:
            module.parse_payload(payload)
        except ValueError as exc:
            assert "Checksum precision mismatch" in str(exc)
        else:
            raise AssertionError(f"Invalid checksum payload was incorrectly accepted: {payload!r}")

    with open(MINIMAL_CRASH_PATH) as f:
        minimized = f.read().strip()
    assert module.parse_payload(minimized) is True, "The repaired parser must handle the minimized former crash"


def test_regression_test_suite_passes_and_detects_each_regression():
    assert os.path.isfile(TEST_PARSER_PATH), f"The regression test file {TEST_PARSER_PATH} is missing."
    with open(MINIMAL_CRASH_PATH) as f:
        minimized = f.read().strip()
    with open(BEACON_PARSER_PATH) as f:
        repaired_source = f.read()

    try:
        result = run_submitted_tests()
        assert result.returncode == 0, (
            f"The regression test suite {TEST_PARSER_PATH} failed to execute successfully.\n"
            f"Output:\n{result.stdout}\n{result.stderr}"
        )

        float_result = suite_result_with_parser(mutant_source(float_bug=True))
        assert float_result.returncode != 0, "The regression suite does not detect the floating-point precision bug"

        empty_result = suite_result_with_parser(mutant_source(empty_bug=True))
        assert empty_result.returncode != 0, "The regression suite does not detect empty/trailing padding crashes"

        minimal_result = suite_result_with_parser(mutant_source(fail_payload=minimized))
        assert minimal_result.returncode != 0, "The regression suite does not exercise minimal_crash.txt"
    finally:
        with open(BEACON_PARSER_PATH, "w") as f:
            f.write(repaired_source)
        shutil.rmtree(os.path.join(WORKSPACE_DIR, "__pycache__"), ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
