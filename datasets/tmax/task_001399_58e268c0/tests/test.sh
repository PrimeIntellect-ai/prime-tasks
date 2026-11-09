#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import pytest


def get_expected_crash_tx():
    dump_path = "/app/memory.dmp"
    if not os.path.exists(dump_path):
        pytest.fail(f"Memory dump missing at {dump_path}")
    with open(dump_path, "rb") as f:
        content = f.read()
        idx = content.find(b"CRASH_TX:")
        if idx != -1:
            return content[idx+9:idx+9+32].decode("ascii")
    pytest.fail("Could not find CRASH_TX in memory dump.")


def get_expected_max_payload():
    image_path = "/app/config_params.png"
    assert os.path.isfile(image_path), f"Configuration image missing at {image_path}"
    result = subprocess.run(
        ["tesseract", image_path, "stdout"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Could not OCR {image_path}: {result.stderr}"
    match = re.search(r"MAX_PAYLOAD\s*=\s*(-?\d+)", result.stdout)
    assert match, f"Could not derive MAX_PAYLOAD from OCR output: {result.stdout!r}"
    return int(match.group(1))


def run_sanitiser(exe_path, args):
    return subprocess.run(
        [exe_path] + args,
        capture_output=True,
        timeout=10,
    )


def test_crash_tx_extracted():
    expected_tx = get_expected_crash_tx()
    out_path = "/home/user/crash_tx.txt"
    assert os.path.isfile(out_path), f"File {out_path} is missing."

    with open(out_path, "r") as f:
        actual_tx = f.read().strip()

    assert actual_tx == expected_tx, f"Expected crash TX '{expected_tx}', but got '{actual_tx}' in {out_path}."


def test_sanitiser_executable_exists():
    exe_path = "/home/user/sanitiser"
    assert os.path.isfile(exe_path), f"Sanitiser executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"Sanitiser {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitiser must be a compiled executable."


def test_sanitiser_source_exists_and_compiles(tmp_path):
    source_path = "/home/user/sanitiser.c"
    assert os.path.isfile(source_path), f"C source {source_path} is missing."
    assert not os.path.islink(source_path), f"C source {source_path} must be a regular file."
    rebuilt = tmp_path / "sanitiser-from-source"
    result = subprocess.run(
        ["gcc", source_path, "-O2", "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"sanitiser.c did not compile with gcc: {result.stderr}"
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)


def test_sanitiser_on_corpora():
    exe_path = "/home/user/sanitiser"
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    assert os.path.isfile(exe_path), "Sanitiser executable not found."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        res = subprocess.run([exe_path, cf], capture_output=True)
        if res.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        res = subprocess.run([exe_path, ef], capture_output=True)
        if res.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_unseen_adversarial_logs_and_argument_count(tmp_path):
    source_path = "/home/user/sanitiser.c"
    submitted = "/home/user/sanitiser"
    assert os.path.isfile(source_path), f"C source {source_path} is missing."
    assert os.path.isfile(submitted), f"Sanitiser executable {submitted} is missing."

    rebuilt = tmp_path / ("rebuilt-" + secrets.token_hex(8))
    compilation = subprocess.run(
        ["gcc", source_path, "-O2", "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compilation.returncode == 0, f"sanitiser.c did not compile with gcc: {compilation.stderr}"

    crash_tx = get_expected_crash_tx()
    max_payload = get_expected_max_payload()
    altered_tx = secrets.token_hex(16)
    while altered_tx == crash_tx:
        altered_tx = secrets.token_hex(16)

    random_tx = lambda: secrets.token_hex(16)
    filler = lambda: secrets.token_hex(secrets.randbelow(48) + 1)
    cases = [
        (f"HEADER:{filler()}\nTX:{random_tx()}\nSIZE:0\n", 0, "zero payload"),
        (f"TX:{random_tx()}\nSIZE:{max_payload}\nTAIL:{filler()}\n", 0, "maximum payload"),
        (f"TX:{altered_tx}\nSIZE:{max(0, max_payload - 1)}\n", 0, "non-crash transaction"),
        (f"TX:{random_tx()}\nSIZE:{max_payload + 1}\nTAIL:{filler()}\n", 1, "payload above maximum"),
        (f"TX:{random_tx()}\nSIZE:-1\nTAIL:{filler()}\n", 1, "negative payload"),
        (f"TX:{random_tx()}\nSIZE:999999999999999999999999999999999999999999\n", 1, "oversized integer"),
        (f"NOTE:{crash_tx}\nSIZE:{max(0, max_payload - 1)}\n", 1, "crash transaction"),
        (f"TX:{random_tx()}\nSIZE:{max(0, max_payload - 2)}\nSIZE:{max_payload + secrets.randbelow(10000) + 1}\n", 1, "later evil size marker"),
    ]

    case_paths = []
    for content, expected, description in cases:
        path = tmp_path / (secrets.token_hex(12) + ".log")
        path.write_text(content)
        case_paths.append((str(path), expected, description))

    rng = random.SystemRandom()
    for exe_path in (submitted, str(rebuilt)):
        assert run_sanitiser(exe_path, []).returncode != 0, f"{exe_path} accepted zero arguments"
        assert run_sanitiser(exe_path, [case_paths[0][0], case_paths[1][0]]).returncode != 0, f"{exe_path} accepted multiple arguments"

        shuffled = case_paths[:]
        rng.shuffle(shuffled)
        for path, expected, description in shuffled:
            result = run_sanitiser(exe_path, [path])
            assert result.returncode == expected, (
                f"{exe_path} misclassified unseen case '{description}': "
                f"expected exit {expected}, got {result.returncode}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
