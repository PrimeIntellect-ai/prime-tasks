#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shutil
import subprocess
import sysconfig
import tempfile

import pytest

SCRIPT = "/home/user/log_classifier.py"
REPO = "/app/math_parser_repo"
SALT = 839201


def c_mod(a, b):
    return a - int(a / b) * b


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_validate_math_parser():
    assert os.path.isdir(REPO), f"Repository missing: {REPO}"
    setup_path = os.path.join(REPO, "setup.py")
    source_path = os.path.join(REPO, "math_parser.c")
    assert os.path.isfile(setup_path), "setup.py is missing"
    assert os.path.isfile(source_path), "math_parser.c is missing"

    with open(setup_path, encoding="utf-8") as f:
        setup_text = f.read()
    assert "/invalid/path/that/breaks/gcc" not in setup_text, "The broken compiler configuration was not repaired"

    shutil.rmtree(os.path.join(REPO, "build"), ignore_errors=True)
    shutil.rmtree(os.path.join(REPO, "MathParser.egg-info"), ignore_errors=True)
    for artifact in glob.glob(os.path.join(REPO, "math_parser*.so")):
        os.remove(artifact)

    install = subprocess.run(
        ["python3", "-m", "pip", "install", "-e", "."],
        cwd=REPO,
        text=True,
        capture_output=True,
    )
    assert install.returncode == 0, f"pip install -e . failed:\n{install.stdout}\n{install.stderr}"

    probe = subprocess.run(
        ["python3", "-c", "import math_parser; print(math_parser.__file__)"],
        cwd="/tmp",
        text=True,
        capture_output=True,
    )
    assert probe.returncode == 0, f"math_parser cannot be imported: {probe.stderr}"
    module_path = probe.stdout.strip().splitlines()[-1]
    extension_suffix = sysconfig.get_config_var("EXT_SUFFIX") or ".so"
    assert module_path.endswith(extension_suffix), f"math_parser is not the built C extension: {module_path}"

    cases = [
        (0, SALT), (1, SALT), (7, SALT), (267, SALT),
        (999982, SALT), (1000003, SALT), (-1, SALT),
        (-317, SALT), (1234567, 19), (7654321, 4441),
    ]
    code = (
        "import json, math_parser, sys; "
        "cases=json.loads(sys.argv[1]); "
        "print(json.dumps([math_parser.compute_hash(a,b) for a,b in cases]))"
    )
    result = subprocess.run(
        ["python3", "-c", code, json.dumps(cases)],
        cwd="/tmp",
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, f"compute_hash failed: {result.stderr}"
    actual = json.loads(result.stdout)
    expected = [c_mod(a * b, 999983) for a, b in cases]
    assert actual == expected, f"math_parser regression remains: expected {expected}, got {actual}"


def run_classifier(path):
    return subprocess.run(["python3", SCRIPT, path], text=True, capture_output=True)


def test_log_classifier_exists():
    assert os.path.isfile(SCRIPT), f"Expected script not found at {SCRIPT}"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failures = []
    for cf in clean_files:
        if run_classifier(cf).returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        if run_classifier(ef).returncode != 1:
            evil_failures.append(os.path.basename(ef))

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_classifier_on_unlabelled_generated_logs():
    with tempfile.TemporaryDirectory(prefix="query-check-") as directory:
        for i in range(24):
            query_value = secrets.randbelow(8_000_001) - 4_000_000
            true_hash = c_mod(query_value * SALT, 999983)
            valid = i % 2 == 0
            reported = true_hash if valid else c_mod(true_hash + secrets.randbelow(999982) + 1, 999983)
            path = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"query_value": query_value, "reported_hash": reported}, f)
            result = run_classifier(path)
            expected_code = 0 if valid else 1
            assert result.returncode == expected_code, (
                f"Classifier returned {result.returncode}, expected {expected_code}, "
                f"for generated input {query_value}; stderr={result.stderr!r}"
            )


def test_classifier_calls_math_parser_with_extracted_salt():
    wrapper = r'''
import json, runpy, sys, types
script, log_path, marker, fake_result = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
module = types.ModuleType("math_parser")
def compute_hash(query_value, salt):
    with open(marker, "w", encoding="utf-8") as f:
        json.dump([query_value, salt], f)
    return fake_result
module.compute_hash = compute_hash
sys.modules["math_parser"] = module
sys.argv = [script, log_path]
runpy.run_path(script, run_name="__main__")
'''
    with tempfile.TemporaryDirectory(prefix="module-check-") as directory:
        query_value = secrets.randbelow(2_000_000) + 2_000_000
        for fake_result, reported, expected_code in [(424242, 424242, 0), (313131, 313132, 1)]:
            log_path = os.path.join(directory, secrets.token_hex(10) + ".json")
            marker = os.path.join(directory, secrets.token_hex(10) + ".marker")
            with open(log_path, "w", encoding="utf-8") as f:
                json.dump({"query_value": query_value, "reported_hash": reported}, f)
            result = subprocess.run(
                ["python3", "-c", wrapper, SCRIPT, log_path, marker, str(fake_result)],
                text=True,
                capture_output=True,
            )
            assert result.returncode == expected_code, (
                "Classifier did not base its decision on math_parser.compute_hash; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert os.path.isfile(marker), "Classifier did not call math_parser.compute_hash"
            with open(marker, encoding="utf-8") as f:
                called_with = json.load(f)
            assert called_with == [query_value, SALT], (
                f"compute_hash must be called with query_value and the extracted salt {SALT}; got {called_with}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
