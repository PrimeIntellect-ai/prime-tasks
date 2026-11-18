#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import string
import subprocess
import tempfile
import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/log_ingestor.c"
BINARY = f"{HOME}/log_ingestor"


def test_solution_txt_content():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"Solution file {solution_path} is missing."

    with open(solution_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) >= 2, "solution.txt must contain at least two lines."
    assert lines[0] == "app_03.log", f"Line 1 of solution.txt is incorrect. Expected 'app_03.log', got '{lines[0]}'."
    assert lines[1] == "63", f"Line 2 of solution.txt is incorrect. Expected '63', got '{lines[1]}'."
    assert len(lines) == 2, "solution.txt must contain exactly two lines."


def test_log_ingestor_c_contains_assert():
    c_file_path = "/home/user/log_ingestor.c"
    assert os.path.isfile(c_file_path), f"Source file {c_file_path} is missing."

    with open(c_file_path, "r") as f:
        content = f.read()

    assert "assert(" in content, "log_ingestor.c must contain an assert() statement."

    # Ignore comments, then require a nonconstant bounds assertion before a
    # filter_log call. Behavioral tests below independently verify sanitization.
    code = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    assertions = list(re.finditer(r"\bassert\s*\((.*?)\)\s*;", code, flags=re.S))
    valid = False
    for match in assertions:
        expr = match.group(1)
        following = code[match.end():]
        call = re.search(r"\bfilter_log\s*\(", following)
        if not call:
            continue
        has_comparison = bool(re.search(r"<=|>=|<|>|==|!=", expr))
        has_bound_or_length = bool(re.search(
            r"\b(?:strlen|strnlen|sizeof)\b|\b(?:len|length|payload|req_id|field|found|line)\w*\b|\b(?:63|64)\b",
            expr,
            flags=re.I,
        ))
        has_identifier = bool(re.search(r"[A-Za-z_]\w*", expr))
        if has_comparison and has_bound_or_length and has_identifier:
            valid = True
            break
    assert valid, "assert() must perform a nonconstant length/bounds validation before filter_log()."


def test_fuzzer_exists_and_runs():
    path = "/home/user/fuzzer.py"
    assert os.path.isfile(path), "Required /home/user/fuzzer.py is missing."
    assert os.path.getsize(path) > 0, "fuzzer.py is empty."

    with open(path, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as exc:
        pytest.fail(f"fuzzer.py is not valid Python: {exc}")

    assert re.search(r"libfilter(?:\.so)?|filter_log|log_ingestor", source, re.I), \
        "fuzzer.py does not exercise the filter library or ingestor."
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                calls.append(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                calls.append(node.func.attr)
    useful_calls = {"run", "Popen", "call", "check_call", "check_output", "system", "fork", "CDLL", "filter_log"}
    assert useful_calls.intersection(calls), "fuzzer.py contains no executable fuzzing/library invocation."

    try:
        result = subprocess.run(
            ["python3", path], cwd=HOME, capture_output=True, text=True, timeout=20
        )
    except subprocess.TimeoutExpired:
        pytest.fail("fuzzer.py timed out instead of completing its crash-condition search.")
    assert result.returncode == 0, \
        f"fuzzer.py failed with exit code {result.returncode}. stdout={result.stdout!r} stderr={result.stderr!r}"


def rebuild_submission():
    result = subprocess.run(
        [
            "gcc", "-o", BINARY, SOURCE,
            "-L/home/user", "-lfilter", "-Wl,-rpath=/home/user",
        ],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"log_ingestor.c did not compile: {result.stderr}"


def test_log_ingestor_compiles_and_runs():
    rebuild_submission()
    binary_path = "/home/user/log_ingestor"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing. Did you recompile?"
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."

    log_file = "/home/user/logs/app_03.log"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

    try:
        result = subprocess.run([binary_path, log_file], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"log_ingestor crashed or returned non-zero exit code {result.returncode} when processing {log_file}."
    except subprocess.TimeoutExpired:
        pytest.fail("log_ingestor timed out when processing the log file.")


def test_randomized_sanitization_and_real_filter_calls():
    rebuild_submission()

    # Interpose filter_log so the verifier can inspect exactly what the rebuilt
    # ingestor passes to the black-box API without invoking its unsafe strcpy.
    spy_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int filter_log(const char *line) {
    const char *path = getenv("FILTER_TRACE");
    if (!path || !line) return 0;
    FILE *f = fopen(path, "a");
    if (!f) return 0;
    const unsigned char *p = (const unsigned char *)line;
    while (*p) { fprintf(f, "%02x", (unsigned int)*p); ++p; }
    fputc('\n', f);
    fclose(f);
    return strstr(line, "REQ_ID:") != NULL;
}
'''
    with tempfile.TemporaryDirectory(prefix="verify_ingestor_") as td:
        spy_c = os.path.join(td, "spy.c")
        spy_so = os.path.join(td, "spy.so")
        trace = os.path.join(td, "trace.txt")
        log = os.path.join(td, "generated.log")
        with open(spy_c, "w") as f:
            f.write(spy_source)
        built = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", spy_so, spy_c],
            capture_output=True, text=True, timeout=20,
        )
        assert built.returncode == 0, built.stderr

        alphabet = string.ascii_letters + string.digits
        token = "".join(random.SystemRandom().choice(alphabet) for _ in range(18))
        short_payload = "".join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(8, 35)))
        long_payload = "".join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(90, 145)))
        embedded_payload = "".join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(75, 120)))
        original = [
            f"INFO verifier-{token}",
            f"REQ_ID:{short_payload}",
            f"REQ_ID:{long_payload}",
            f"PREFIX-{token} REQ_ID:{embedded_payload}",
        ]
        with open(log, "w") as f:
            for line in original:
                f.write(line + "\n")

        env = os.environ.copy()
        env["LD_PRELOAD"] = spy_so
        env["FILTER_TRACE"] = trace
        try:
            result = subprocess.run([BINARY, log], env=env, capture_output=True, text=True, timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail("Rebuilt log_ingestor timed out on generated input.")
        assert result.returncode == 0, \
            f"Rebuilt log_ingestor failed on generated input: {result.returncode}, {result.stderr}"
        assert os.path.isfile(trace), "filter_log was never called by the rebuilt ingestor."

        with open(trace, "r") as f:
            passed = [bytes.fromhex(line.strip()).decode("utf-8") for line in f if line.strip()]
        assert len(passed) == len(original), \
            f"Expected one filter_log call per input line, observed {len(passed)} for {len(original)} lines."

        for source_line, passed_line in zip(original, passed):
            normalized = passed_line[:-1] if passed_line.endswith("\n") else passed_line
            marker = "REQ_ID:"
            if marker not in source_line:
                assert normalized == source_line, "A normal log line was not passed intact to filter_log."
                continue

            prefix, payload = source_line.split(marker, 1)
            assert normalized.startswith(prefix + marker), \
                "The ingestor changed or discarded data preceding the vulnerable field."
            sanitized_payload = normalized[len(prefix + marker):]
            assert len(sanitized_payload) <= 63, \
                f"Oversized REQ_ID reached filter_log with length {len(sanitized_payload)}."
            expected = payload[:63]
            assert sanitized_payload == expected, \
                "REQ_ID was not preserved up to, and truncated exactly at, the maximum safe length."


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
