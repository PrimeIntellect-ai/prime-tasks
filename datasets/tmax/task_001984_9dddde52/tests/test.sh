#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import secrets
import stat
import string
import subprocess
import tempfile
import time

FILTER = "/home/user/security_filter.py"
MAKEFILE = "/home/user/Makefile"
TEST_SCRIPT = "/home/user/test_filter.py"


def run_filter(file_path):
    result = subprocess.run(
        ["python3", FILTER, file_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.returncode


def check_text(text, expected):
    name = "case_" + secrets.token_hex(12) + ".txt"
    path = os.path.join(tempfile.gettempdir(), name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    try:
        assert run_filter(path) == expected, repr(text)
    finally:
        os.unlink(path)


def test_security_filter_exists():
    assert os.path.isfile(FILTER), f"Security filter not found at {FILTER}"


def test_security_filter_clean_corpus():
    clean_dir = "/app/eval_corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No clean corpus files found."
    failed_files = [f for f in clean_files if run_filter(os.path.join(clean_dir, f)) != 0]
    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files rejected (expected exit code 0). Offending files: {failed_files}"


def test_security_filter_evil_corpus():
    evil_dir = "/app/eval_corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No evil corpus files found."
    failed_files = [f for f in evil_files if run_filter(os.path.join(evil_dir, f)) != 1]
    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1). Offending files: {failed_files}"


def test_security_filter_generated_clean_inputs():
    alphabet = string.ascii_letters + string.digits
    for _ in range(30):
        value = "".join(secrets.choice(alphabet) for _ in range(random.randint(0, 300)))
        check_text(value, 0)


def test_security_filter_generated_aws_keys():
    alphabet = string.ascii_uppercase + string.digits
    for _ in range(12):
        key = "AKIA" + "".join(secrets.choice(alphabet) for _ in range(16))
        check_text("credential=" + key + "\n", 1)


def test_security_filter_generated_stack_traces():
    for marker in ("Traceback", "Exception"):
        for _ in range(6):
            prefix = secrets.token_hex(8)
            suffix = secrets.token_hex(8)
            check_text(prefix + " " + marker + " " + suffix, 1)


def test_security_filter_generated_tags():
    tag = "x" + secrets.token_hex(5)
    cases = [
        f"before <{tag}>inside</{tag}> after",
        f"image <img src=\"{secrets.token_hex(4)}.png\"> end",
        f"node <div class=\"{secrets.token_hex(4)}\">text</div>",
        f"xml <{tag} attr='value'/> tail",
    ]
    for value in cases:
        check_text(value, 1)


def test_security_filter_generated_internal_ips():
    for _ in range(12):
        ip10 = f"10.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(0,255)}"
        ip192 = f"192.168.{random.randint(0,255)}.{random.randint(0,255)}"
        check_text("host=" + ip10, 1)
        check_text("endpoint " + ip192 + " unavailable", 1)


def test_make_check_fails_after_real_recipe_steps():
    assert os.path.isfile(MAKEFILE), "Makefile not found at /home/user/Makefile"

    dry = subprocess.run(
        ["make", "-n", "check"], cwd="/home/user", capture_output=True, text=True, timeout=20
    )
    assert dry.returncode == 0, f"The check target is not a valid make target:\n{dry.stdout}\n{dry.stderr}"
    recipe = dry.stdout + dry.stderr
    assert re.search(r"(?:^|[ /])tesseract(?:\s|$)", recipe), "check target does not invoke tesseract"
    assert "/app/screenshot.png" in recipe, "check target does not OCR /app/screenshot.png"
    assert "security_filter.py" in recipe, "check target does not run security_filter.py"
    assert "screenshot_text.txt" in recipe, "check target does not filter screenshot_text.txt"
    assert re.search(r"python3[^\n]*security_filter\.py[^\n]*screenshot_text\.txt", recipe), "check target must run python3 security_filter.py on screenshot_text.txt"

    output = "/home/user/screenshot_text.txt"
    if os.path.lexists(output):
        os.unlink(output)
    started = time.time()
    result = subprocess.run(
        ["make", "check"], cwd="/home/user", capture_output=True, text=True, timeout=60
    )
    assert result.returncode != 0, "make check should fail because the screenshot contains leaked info."
    assert os.path.isfile(output), "make check did not create screenshot_text.txt"
    assert os.path.getmtime(output) >= started - 1, "screenshot_text.txt was not freshly generated"
    with open(output, encoding="utf-8", errors="replace") as f:
        ocr = f.read()
    assert re.search(r"Dashboard|Welcome", ocr, re.IGNORECASE), f"screenshot_text.txt does not contain OCR output: {ocr!r}"
    assert re.search(r"Exception|192[.,]168", ocr, re.IGNORECASE), f"OCR output omitted the screenshot leak: {ocr!r}"


def test_hypothesis_script_runs_and_tests_property():
    assert os.path.isfile(TEST_SCRIPT), f"Test script not found at {TEST_SCRIPT}"
    source = open(TEST_SCRIPT, encoding="utf-8").read()
    tree = ast.parse(source, TEST_SCRIPT)

    imports_hypothesis = any(
        (isinstance(n, ast.Import) and any(a.name == "hypothesis" or a.name.startswith("hypothesis.") for a in n.names))
        or (isinstance(n, ast.ImportFrom) and n.module and (n.module == "hypothesis" or n.module.startswith("hypothesis.")))
        for n in ast.walk(tree)
    )
    assert imports_hypothesis, "test_filter.py must import hypothesis"

    functions = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test")]
    assert functions, "test_filter.py must define a pytest test"
    decorated = []
    for fn in functions:
        for dec in fn.decorator_list:
            text = ast.unparse(dec)
            if re.search(r"(^|\.)given\s*\(", text):
                decorated.append(fn)
    assert decorated, "A test must be decorated with Hypothesis @given(...)"
    assert any(any(isinstance(n, ast.Assert) for n in ast.walk(fn)) for fn in decorated), "The Hypothesis test must contain an assertion"
    assert "security_filter" in source, "The property test must exercise the security filter"
    assert re.search(r"strategies|\bst\.|characters|text\s*\(", source), "The property test must use a Hypothesis string strategy"

    direct = subprocess.run(["python3", TEST_SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=60)
    assert direct.returncode == 0, f"test_filter.py failed to run successfully.\nStdout: {direct.stdout}\nStderr: {direct.stderr}"

    normal = subprocess.run(["python3", "-m", "pytest", "-q", TEST_SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=120)
    assert normal.returncode == 0, f"Hypothesis tests failed.\nStdout: {normal.stdout}\nStderr: {normal.stderr}"
    assert "no tests ran" not in (normal.stdout + normal.stderr).lower(), "No Hypothesis test was collected"

    original = open(FILTER, "rb").read()
    original_mode = stat.S_IMODE(os.stat(FILTER).st_mode)
    try:
        with open(FILTER, "w", encoding="utf-8") as f:
            f.write("#!/usr/bin/env python3\nimport sys\ndef is_safe(*args, **kwargs): return False\ndef evaluate(*args, **kwargs): return False\ndef check(*args, **kwargs): return False\nif __name__ == '__main__': sys.exit(1)\n")
        os.chmod(FILTER, original_mode)
        mutant = subprocess.run(["python3", "-m", "pytest", "-q", TEST_SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=120)
        assert mutant.returncode != 0, "The property test did not detect a filter that rejects every generated alphanumeric string"
    finally:
        with open(FILTER, "wb") as f:
            f.write(original)
        os.chmod(FILTER, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
