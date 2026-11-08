#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/validate_telemetry.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
VIDEO_PATH = "/app/calibration.mp4"


def get_modulo():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
            "-show_entries", "stream=nb_read_frames",
            "-of", "default=noprint_wrappers=1:nokey=1", VIDEO_PATH,
        ],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    values = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(values) == 1 and values[0].isdigit(), f"Could not derive frame count: {result.stdout!r}"
    modulo = int(values[0]) % 100
    assert modulo > 1, f"Calibration video produced unusable test modulo {modulo}"
    return modulo


M = get_modulo()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"
    with open(SCRIPT_PATH, "rb") as script:
        first_line = script.readline(256).decode("utf-8", "replace").lower()
    assert first_line.startswith("#!") and "bash" in first_line, "Submission must be a Bash script"


def run_script_args(*args):
    result = subprocess.run(
        [SCRIPT_PATH, *args],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    )
    return result.returncode


def run_script_with_url(url):
    return run_script_args(url)


def test_clean_corpus():
    """Asserts that all clean URLs are accepted (exit code 0)."""
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}"

    failed_files = []
    total_files = 0

    for filename in sorted(os.listdir(CLEAN_CORPUS_DIR)):
        file_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        if not os.path.isfile(file_path):
            continue

        with open(file_path, "r") as f:
            url = f.read().strip()

        total_files += 1
        exit_code = run_script_with_url(url)

        if exit_code != 0:
            failed_files.append((filename, url, exit_code))

    if failed_files:
        error_msg = f"{len(failed_files)} of {total_files} clean modified/rejected.\nOffending files:\n"
        for fname, url, code in failed_files:
            error_msg += f"  - {fname} (exit code {code}) for URL: {url}\n"
        pytest.fail(error_msg)


def test_evil_corpus():
    """Asserts that all evil URLs are rejected with exactly exit code 1."""
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing at {EVIL_CORPUS_DIR}"

    failed_files = []
    total_files = 0

    for filename in sorted(os.listdir(EVIL_CORPUS_DIR)):
        file_path = os.path.join(EVIL_CORPUS_DIR, filename)
        if not os.path.isfile(file_path):
            continue

        with open(file_path, "r") as f:
            url = f.read().strip()

        total_files += 1
        exit_code = run_script_with_url(url)

        if exit_code != 1:
            failed_files.append((filename, url, exit_code))

    if failed_files:
        error_msg = f"{len(failed_files)} of {total_files} evil requests did not return exit code 1.\nOffending files:\n"
        for fname, url, code in failed_files:
            error_msg += f"  - {fname} (exit code {code}) for URL: {url}\n"
        pytest.fail(error_msg)


def test_random_valid_requests():
    for i in range(24):
        x = 1 + secrets.randbelow(1_000_000)
        y = (-x) % M
        if y == 0:
            y = M
        action = secrets.choice(("calculate", "update"))
        if i % 2:
            query = f"y={y}&x={x}"
        else:
            query = f"x={x}&y={y}"
        url = f"/api/v1/route/{action}?{query}"
        assert run_script_with_url(url) == 0, f"Valid generated URL was rejected: {url}"


def test_random_nondivisible_requests_return_one():
    for _ in range(24):
        x = 1 + secrets.randbelow(1_000_000)
        y = 1 + secrets.randbelow(1_000_000)
        if (x + y) % M == 0:
            y += 1
        action = secrets.choice(("calculate", "update"))
        url = f"/api/v1/route/{action}?x={x}&y={y}"
        assert run_script_with_url(url) == 1, f"Non-divisible URL did not return 1: {url}"


def test_malformed_and_malicious_requests_return_one():
    x = M
    y = M
    marker = f"/tmp/telemetry_injection_{secrets.token_hex(12)}"
    bad_urls = [
        f"/api/v1/route/delete?x={x}&y={y}",
        f"/api/v1/route/Calculate?x={x}&y={y}",
        f"/api/v1/route/calculate/extra?x={x}&y={y}",
        f"/api/v1/route/../calculate?x={x}&y={y}",
        f"/api/v1/route/%63alculate?x={x}&y={y}",
        f"/api/v1/route/calculate?x={x}&y={y}%20",
        "/api/v1/route/calculate",
        "/api/v1/route/calculate?",
        f"/api/v1/route/calculate?x={x}",
        f"/api/v1/route/calculate?y={y}",
        f"/api/v1/route/calculate?x={x}&y={y}&z=1",
        f"/api/v1/route/calculate?x={x}&x={x}&y={y}",
        f"/api/v1/route/calculate?x={x}&y={y}&y={y}",
        f"/api/v1/route/calculate?x={x}&y={y}&",
        f"/api/v1/route/calculate?x={x}&&y={y}",
        f"/api/v1/route/calculate?x={x};y={y}",
        f"/api/v1/route/calculate?x=0&y={y}",
        f"/api/v1/route/calculate?x=-{x}&y={y + x}",
        f"/api/v1/route/calculate?x=+{x}&y={y}",
        f"/api/v1/route/calculate?x={x}.0&y={y}",
        f"/api/v1/route/calculate?x= {x}&y={y}",
        f"/api/v1/route/calculate?x={x}&y={y}#fragment",
        f"/api/v1/route/calculate?x=$({{touch,{marker}}})&y={y}",
        f"/api/v1/route/update?x=`touch {marker}`&y={y}",
    ]
    for url in bad_urls:
        assert run_script_with_url(url) == 1, f"Malformed URL did not return exit code 1: {url!r}"
    assert not os.path.exists(marker), "Rejected command-injection input was executed"


def test_argument_count_errors_return_one():
    assert run_script_args() == 1, "Missing URL argument must return exit code 1"
    valid = f"/api/v1/route/calculate?x={M}&y={M}"
    assert run_script_args(valid, valid) == 1, "More than one argument must return exit code 1"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
