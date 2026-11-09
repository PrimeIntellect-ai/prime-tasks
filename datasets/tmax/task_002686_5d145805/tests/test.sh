#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

EVIL_DIR = "/home/user/corpus/evil"
CLEAN_DIR = "/home/user/corpus/clean"
WAF_SCRIPT = "/home/user/waf.py"
GENERATED_DIR = tempfile.mkdtemp(prefix="waf_mixed_")


def make_elf(malicious):
    # Same ELF fields and anomaly used by the supplied corpus, but encoded in
    # fresh requests without the fixed EVIL_SHELLCODE marker.
    prefix = (
        b"\x7fELF\x02\x01\x01\x00"
        b"\x00\x00\x00\x00\x00\x00\x00\x00"
        b"\x02\x00\x3e\x00\x01\x00\x00\x00"
    )
    entry = b"\xff" * 8 if malicious else b"\x00" * 8
    return prefix + entry + b"DATA_" + secrets.token_hex(12).encode("ascii")


def escaped(data):
    return b"".join(("\\x%02x" % byte).encode("ascii") for byte in data)


def build_generated_cases():
    cases = []
    # Both classes use both representations, equal lengths, and opaque names.
    for malicious in (False, True):
        for encoded in (False, True):
            for _ in range(5):
                elf = make_elf(malicious)
                upload_body = escaped(elf) if encoded else elf
                newline = secrets.choice([b"\n", b"\r\n"])
                headers = [
                    b"Host: localhost:8080",
                    b"Content-Type: application/octet-stream",
                    b"Content-Length: " + str(len(upload_body)).encode("ascii"),
                    b"X-Request-ID: " + secrets.token_hex(10).encode("ascii"),
                ]
                secrets.SystemRandom().shuffle(headers)
                raw_request = (
                    b"POST /upload HTTP/1.1" + newline
                    + newline.join(headers) + newline + newline + upload_body
                )
                filename = secrets.token_hex(16) + ".req"
                with open(os.path.join(GENERATED_DIR, filename), "wb") as handle:
                    handle.write(raw_request)
                cases.append({
                    "filename": filename,
                    "malicious": malicious,
                    "upload_body": upload_body,
                })
    secrets.SystemRandom().shuffle(cases)
    return cases


GENERATED_CASES = build_generated_cases()
GENERATED_EXPECTED = {case["filename"]: case["malicious"] for case in GENERATED_CASES}


def run_waf(input_dir, output_file):
    assert os.path.isfile(WAF_SCRIPT), f"WAF script not found at {WAF_SCRIPT}"
    if os.path.exists(output_file):
        os.unlink(output_file)
    result = subprocess.run(
        ["python3", WAF_SCRIPT, "--input-dir", input_dir, "--output-file", output_file],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"WAF script failed for {input_dir}:\n{result.stderr}\n{result.stdout}"
    )
    assert os.path.isfile(output_file), f"WAF script did not create {output_file}"


def load_results(path):
    with open(path, "r") as handle:
        try:
            results = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {path} is not valid JSON.")
    assert isinstance(results, dict), "Output JSON must be a dictionary"
    return results


def test_waf_script_evil_corpus():
    output_file = "/home/user/evil_results.json"
    run_waf(EVIL_DIR, output_file)
    results = load_results(output_file)

    evil_files = os.listdir(EVIL_DIR)
    bypassed = []
    for filename in evil_files:
        if filename not in results:
            bypassed.append(f"{filename} (missing)")
        elif type(results[filename]) is not bool:
            bypassed.append(f"{filename} (not boolean)")
        elif not results[filename]:
            bypassed.append(filename)

    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}"
        )


def test_waf_script_clean_corpus():
    output_file = "/home/user/clean_results.json"
    run_waf(CLEAN_DIR, output_file)
    results = load_results(output_file)

    clean_files = os.listdir(CLEAN_DIR)
    modified = []
    for filename in clean_files:
        if filename not in results:
            modified.append(f"{filename} (missing)")
        elif type(results[filename]) is not bool:
            modified.append(f"{filename} (not boolean)")
        elif results[filename]:
            modified.append(filename)

    if modified:
        pytest.fail(
            f"{len(modified)} of {len(clean_files)} clean modified (rejected): "
            + ", ".join(modified)
        )


def test_waf_script_unseen_mixed_corpus():
    output_file = os.path.join(tempfile.gettempdir(), secrets.token_hex(12) + ".json")
    run_waf(GENERATED_DIR, output_file)
    results = load_results(output_file)

    errors = []
    for filename, expected in GENERATED_EXPECTED.items():
        if filename not in results:
            errors.append(f"{filename} (missing)")
        elif type(results[filename]) is not bool:
            errors.append(f"{filename} (not boolean)")
        elif results[filename] is not expected:
            errors.append(f"{filename} (wrong classification)")

    if errors:
        pytest.fail(f"Unseen mixed corpus failures: {', '.join(errors)}")


def stop_services():
    subprocess.run(["pkill", "-f", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "/home/user/app/app.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "/home/user/waf.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(1)


def send_upload(data, malicious, label, bypassed, modified):
    req = urllib.request.Request(
        "http://localhost:8080/upload",
        data=data,
        method="POST",
        headers={"Content-Type": "application/octet-stream"},
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            if malicious:
                bypassed.append(label)
            elif response.status != 200:
                modified.append(f"{label} (HTTP {response.status})")
    except urllib.error.HTTPError as exc:
        if malicious:
            if exc.code != 403:
                bypassed.append(f"{label} (HTTP {exc.code})")
        else:
            modified.append(f"{label} (HTTP {exc.code})")
    except Exception as exc:
        # Preserve the original behavior for rejected malicious requests, while
        # requiring every clean request to remain available.
        if not malicious:
            modified.append(f"{label} (Error: {exc})")


def test_end_to_end_services():
    start_script = "/home/user/start_services.sh"
    assert os.path.exists(start_script), f"Start script not found at {start_script}"

    stop_services()
    subprocess.Popen(
        ["bash", start_script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(5)

    live_cases = []
    for filename in os.listdir(EVIL_DIR):
        with open(os.path.join(EVIL_DIR, filename), "rb") as handle:
            live_cases.append((handle.read(), True, f"original/{filename}"))
    for filename in os.listdir(CLEAN_DIR):
        with open(os.path.join(CLEAN_DIR, filename), "rb") as handle:
            live_cases.append((handle.read(), False, f"original/{filename}"))
    for case in GENERATED_CASES:
        live_cases.append((
            case["upload_body"],
            case["malicious"],
            f"generated/{case['filename']}",
        ))

    secrets.SystemRandom().shuffle(live_cases)
    bypassed = []
    modified = []
    try:
        for data, malicious, label in live_cases:
            send_upload(data, malicious, label, bypassed, modified)
    finally:
        stop_services()

    errors = []
    if bypassed:
        errors.append(
            f"{len(bypassed)} malicious uploads bypassed in live service: "
            + ", ".join(bypassed)
        )
    if modified:
        errors.append(
            f"{len(modified)} clean uploads blocked in live service: "
            + ", ".join(modified)
        )
    if errors:
        pytest.fail("; ".join(errors))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
