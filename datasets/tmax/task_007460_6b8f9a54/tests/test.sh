#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import subprocess
import tempfile

import pytest

REPO = "/home/user/pr_review"
LIB = os.path.join(REPO, "libdetector.so")
SCANNER = os.path.join(REPO, "scanner")


@pytest.fixture(scope="session", autouse=True)
def rebuild_artifacts():
    makefile_path = os.path.join(REPO, "Makefile")
    assert os.path.isfile(makefile_path), f"Expected file {makefile_path} is missing. You must create a Makefile."

    for path in (LIB, SCANNER):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["make", "-B"],
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"The Makefile failed to build the project:\n{result.stdout}"


def test_makefile_exists():
    makefile_path = "/home/user/pr_review/Makefile"
    assert os.path.isfile(makefile_path), f"Expected file {makefile_path} is missing. You must create a Makefile."


def test_libdetector_so_exists():
    lib_path = "/home/user/pr_review/libdetector.so"
    assert os.path.isfile(lib_path), f"Expected shared library {lib_path} is missing. Ensure your Makefile compiles the C++ code into this shared object."
    with open(lib_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libdetector.so is not an ELF shared library."


def test_scanner_executable_exists():
    scanner_path = "/home/user/pr_review/scanner"
    assert os.path.isfile(scanner_path), f"Expected executable {scanner_path} is missing. Ensure your Makefile compiles the Go code into this executable."
    assert os.access(scanner_path, os.X_OK), f"The file {scanner_path} is not executable."
    with open(scanner_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "scanner is not a compiled ELF executable."


def test_detect_threat_export_and_behavior():
    detector = ctypes.CDLL(LIB)
    try:
        detect = detector.detect_threat
    except AttributeError as exc:
        pytest.fail(f"libdetector.so does not export the C ABI symbol detect_threat: {exc}")

    detect.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    detect.restype = ctypes.c_int

    fixed_cases = [
        ("prefix union select suffix", "union select\nscript alert\n", 1),
        ("select only", "union select\nscript alert\n", 0),
        ("alert script extra", "union select\nscript alert\n", 1),
        ("selection reunion", "union select\n", 0),
        ("alpha beta", "gamma delta\nalpha beta gamma\n", 0),
        ("alpha beta gamma", "gamma delta\nalpha beta\n", 1),
    ]
    for payload, signatures, expected in fixed_cases:
        actual = detect(payload.encode(), signatures.encode())
        assert actual == expected, (
            f"detect_threat({payload!r}, {signatures!r}) returned {actual}, expected {expected}"
        )

    rng = random.Random(92741)
    vocabulary = [f"token{i}" for i in range(18)]
    for _ in range(50):
        payload_tokens = rng.sample(vocabulary, rng.randint(0, 10))
        signature_rows = [
            rng.sample(vocabulary, rng.randint(1, 5))
            for _ in range(rng.randint(1, 6))
        ]
        expected = int(any(set(row).issubset(set(payload_tokens)) for row in signature_rows))
        payload = " ".join(payload_tokens)
        signatures = "\n".join(" ".join(row) for row in signature_rows) + "\n"
        actual = detect(payload.encode(), signatures.encode())
        assert actual == expected, (
            f"Randomized detector case failed: payload={payload!r}, "
            f"signatures={signatures!r}, expected={expected}, actual={actual}"
        )


def run_scanner(cwd):
    env = os.environ.copy()
    old_ld = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = REPO + ((":" + old_ld) if old_ld else "")
    return subprocess.run(
        [SCANNER],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def test_scanner_runs_on_repository_inputs():
    result = run_scanner(REPO)
    assert result.returncode == 0, f"scanner failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    ids = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert sorted(ids, key=int) == ["2", "3", "5"], f"scanner emitted incorrect IDs: {ids}"


def test_scanner_on_derived_inputs():
    signatures = [
        ["violet", "cedar"],
        ["quartz", "ember", "north"],
        ["delta", "lima"],
    ]
    payload_rows = [
        ("41", "safe violet only"),
        ("7", "north quartz extra ember"),
        ("103", "cedar and violet together"),
        ("22", "delta unrelated"),
        ("58", "lima delta trailing"),
        ("9", "quartz ember without final token"),
    ]
    expected = sorted(
        [
            row_id
            for row_id, payload in payload_rows
            if any(set(sig).issubset(set(payload.split())) for sig in signatures)
        ],
        key=int,
    )

    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "signatures.txt"), "w") as f:
            f.write("\n".join(" ".join(sig) for sig in signatures) + "\n")
        with open(os.path.join(tmp, "payloads.csv"), "w") as f:
            for row_id, payload in payload_rows:
                f.write(f"{row_id},{payload}\n")

        result = run_scanner(tmp)

    assert result.returncode == 0, f"scanner failed on derived inputs:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert sorted(actual, key=int) == expected, (
        f"scanner produced incorrect results for derived inputs; expected {expected}, got {actual}"
    )


def test_alerts_txt_exact_contents():
    alerts_path = "/home/user/alerts.txt"
    assert os.path.isfile(alerts_path), f"Expected output file {alerts_path} is missing. Did you run the scanner and redirect its output?"

    with open(alerts_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_ids = ["2", "3", "5"]

    assert lines == expected_ids, (
        f"The contents of {alerts_path} do not match the expected output.\n"
        f"Expected: {expected_ids}\n"
        f"Actual:   {lines}\n"
        "Ensure that the C++ logic correctly identifies threats, and that the final output is sorted numerically."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
