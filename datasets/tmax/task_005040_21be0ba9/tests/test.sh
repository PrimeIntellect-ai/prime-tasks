#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import secrets
import stat
import string
import subprocess
import tempfile

BINARY_PATH = "/home/user/path_filter"
SOURCE_PATH = "/home/user/path_filter.c"
SCRIPT_PATH = "/home/user/test_restores.sh"
CLEAN_DIR = "/app/hidden_tests/clean"
EVIL_DIR = "/app/hidden_tests/evil"
PREFIX = "/archive/trusted/"
SHELL_METACHARS = set(";&|`$><*?(){}[]!\\")


def run_program(program, args, timeout=2):
    try:
        result = subprocess.run([program] + list(args), capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1
    except Exception as exc:
        return str(exc), -1


def run_filter(path_str):
    return run_program(BINARY_PATH, [path_str])


def policy_accepts(path):
    if len(path) > 256 or not path.startswith(PREFIX) or ".." in path:
        return False
    if any(ch in SHELL_METACHARS for ch in path):
        return False
    if path.endswith(".tar.gz"):
        stem = path[path.rfind("/") + 1:-7]
    elif path.endswith(".bak"):
        stem = path[path.rfind("/") + 1:-4]
    else:
        return False
    return bool(stem) and re.fullmatch(r"[A-Za-z0-9_]+", stem) is not None


def generated_cases():
    token = secrets.token_hex(8)
    valid = [
        f"{PREFIX}{token}.bak",
        f"{PREFIX}daily/{token}_A9.tar.gz",
        f"{PREFIX}region_{token}/nested/Backup_01.bak",
        PREFIX + ("A" * (256 - len(PREFIX) - len(".bak"))) + ".bak",
    ]
    alphabet = string.ascii_letters + string.digits + "_"
    for _ in range(35):
        stem = "".join(secrets.choice(alphabet) for _ in range(8 + secrets.randbelow(30)))
        directory = "set_" + secrets.token_hex(3) + "/"
        extension = ".bak" if secrets.randbelow(2) == 0 else ".tar.gz"
        valid.append(PREFIX + directory + stem + extension)

    invalid = [
        f"/backup/trusted/{token}.bak",
        f"/archive/trustedness/{token}.bak",
        f"{PREFIX}{token}.zip",
        f"{PREFIX}{token}.BAK",
        f"{PREFIX}{token}-bad.bak",
        f"{PREFIX}{token} bad.tar.gz",
        f"{PREFIX}.bak",
        f"{PREFIX}../{token}.bak",
        f"{PREFIX}safe/../../{token}.tar.gz",
        f"{PREFIX}semi;colon/{token}.bak",
        f"{PREFIX}pipe|name/{token}.bak",
        f"{PREFIX}cash$dir/{token}.tar.gz",
        f"{PREFIX}cmd`id`/{token}.bak",
        PREFIX + ("B" * (257 - len(PREFIX) - len(".bak"))) + ".bak",
    ]
    for path in valid[:25]:
        invalid.extend([
            path + ".old",
            path.replace(PREFIX, "/archive/untrusted/", 1),
            PREFIX + "../escape/" + secrets.token_hex(4) + ".bak",
        ])

    cases = [(path, True) for path in valid] + [(path, False) for path in invalid]
    assert all(policy_accepts(path) == expected for path, expected in cases)
    return cases


def assert_cases(program, cases):
    failures = []
    for path, expected in cases:
        out, rc = run_program(program, [path])
        wanted_out, wanted_rc = ("ACCEPT", 0) if expected else ("REJECT", 1)
        if out != wanted_out or rc != wanted_rc:
            failures.append((path, out, rc, wanted_out, wanted_rc))
    assert not failures, f"Policy failures: {failures[:10]}"


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    assert not os.path.islink(BINARY_PATH), "Compiled binary must be a regular file"
    with open(BINARY_PATH, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "path_filter is not a compiled ELF binary"


def test_source_exists_compiles_and_implements_policy():
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "path_filter")
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", rebuilt],
            capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"C source failed to compile: {result.stderr}"
        assert_cases(rebuilt, generated_cases())
        for args in ([], [PREFIX + "one.bak", PREFIX + "two.bak"]):
            out, rc = run_program(rebuilt, args)
            assert out == "REJECT" and rc == 1, f"Incorrect handling of argument count {len(args)}: {out!r}, rc={rc}"


def test_generated_adversarial_policy_cases():
    assert_cases(BINARY_PATH, generated_cases())
    for args in ([], [PREFIX + "one.bak", PREFIX + "two.bak"]):
        out, rc = run_program(BINARY_PATH, args)
        assert out == "REJECT" and rc == 1, f"Incorrect handling of argument count {len(args)}: {out!r}, rc={rc}"


def test_clean_corpus():
    clean_failures = []
    total_clean = 0
    assert os.path.isdir(CLEAN_DIR), f"Clean test directory missing: {CLEAN_DIR}"
    for root, _, files in os.walk(CLEAN_DIR):
        for file in files:
            file_path = os.path.join(root, file)
            with open(file_path, 'r') as f:
                for line in f:
                    line = line.strip('\n')
                    if not line:
                        continue
                    total_clean += 1
                    out, rc = run_filter(line)
                    if out != "ACCEPT" or rc != 0:
                        clean_failures.append(f"'{line}' (out: {out}, rc: {rc})")
    assert total_clean > 0, "No clean corpus cases were found"
    assert not clean_failures, f"{len(clean_failures)} of {total_clean} clean paths incorrectly rejected or failed: {clean_failures[:10]}"


def test_evil_corpus():
    evil_failures = []
    total_evil = 0
    assert os.path.isdir(EVIL_DIR), f"Evil test directory missing: {EVIL_DIR}"
    for root, _, files in os.walk(EVIL_DIR):
        for file in files:
            file_path = os.path.join(root, file)
            with open(file_path, 'r') as f:
                for line in f:
                    line = line.strip('\n')
                    if not line:
                        continue
                    total_evil += 1
                    out, rc = run_filter(line)
                    if out != "REJECT" or rc != 1:
                        evil_failures.append(f"'{line}' (out: {out}, rc: {rc})")
    assert total_evil > 0, "No evil corpus cases were found"
    assert not evil_failures, f"{len(evil_failures)} of {total_evil} evil paths incorrectly accepted or bypassed: {evil_failures[:10]}"


def test_automation_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Automation script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_automation_script_behavior_and_filter_invocation():
    token = secrets.token_hex(6)
    paths = [
        f"{PREFIX}{token}.bak",
        f"{PREFIX}jobs/{token}_2.tar.gz",
        f"{PREFIX}ok/{token}_3.bak",
        f"{PREFIX}{token}-bad.bak",
        f"{PREFIX}../{token}.bak",
        f"/wrong/prefix/{token}.bak",
        f"{PREFIX}{token}.zip",
    ]
    expected = {path: policy_accepts(path) for path in paths}
    valid_count = sum(expected.values())
    invalid_count = len(paths) - valid_count

    with tempfile.TemporaryDirectory() as temp_dir:
        corpus = os.path.join(temp_dir, "paths.txt")
        log_path = os.path.join(temp_dir, "calls.log")
        backup = os.path.join(temp_dir, "original_filter")
        with open(corpus, "w") as handle:
            handle.write("\n".join(paths) + "\n")

        os.replace(BINARY_PATH, backup)
        try:
            wrapper = """#!/usr/bin/env python3
import json, sys
mapping = json.loads(%r)
with open(%r, 'a') as log:
    if len(sys.argv) > 1:
        log.write(sys.argv[1] + '\\n')
if len(sys.argv) == 2 and sys.argv[1] in mapping and mapping[sys.argv[1]]:
    print('ACCEPT')
    raise SystemExit(0)
print('REJECT')
raise SystemExit(1)
""" % (json.dumps(json.dumps(expected)), log_path)
            with open(BINARY_PATH, "w") as handle:
                handle.write(wrapper)
            os.chmod(BINARY_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                                  stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

            result = subprocess.run([SCRIPT_PATH, corpus], capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, f"Automation script failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
            assert re.search(rf"(?mi)^\s*Total valid\s*:?\s*{valid_count}\s*$", result.stdout), result.stdout
            assert re.search(rf"(?mi)^\s*Total invalid\s*:?\s*{invalid_count}\s*$", result.stdout), result.stdout
            with open(log_path) as handle:
                called = [line.rstrip("\n") for line in handle]
            counts = collections.Counter(called)
            assert all(counts[path] >= 1 for path in paths), "Script did not process every input through /home/user/path_filter"
            assert set(called).issubset(set(paths)), "Script passed unexpected paths to path_filter"
        finally:
            if os.path.lexists(BINARY_PATH):
                os.unlink(BINARY_PATH)
            os.replace(backup, BINARY_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
