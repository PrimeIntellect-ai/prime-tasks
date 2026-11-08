#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile

BINARY = "/home/user/log_classifier"
SOURCE = "/home/user/log_classifier.cpp"
SQLI = re.compile(r"(UNION.*SELECT|SELECT.*FROM|DROP.*TABLE)", re.IGNORECASE)
XSS = re.compile(r"(<script.*?>|javascript:|onerror=)", re.IGNORECASE)


def run_classifier(binary, path):
    return subprocess.run(
        [binary, path], capture_output=True, text=True, timeout=5
    )


def expected_for(content):
    return ("REJECT", 1) if SQLI.search(content) or XSS.search(content) else ("ACCEPT", 0)


def test_classifier_exists():
    assert os.path.isfile(BINARY), f"The classifier binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"The classifier binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The classifier must be a compiled ELF executable."
    assert os.path.isfile(SOURCE), f"The classifier source {SOURCE} does not exist."


def test_re2_archive_and_source_linkage():
    candidates = [
        "/app/re2-src/obj/libre2.a",
        "/app/re2-src/build/libre2.a",
        "/app/re2-src/libre2.a",
    ]
    archives = [p for p in candidates if os.path.isfile(p)]
    assert archives, "The compiled RE2 static archive libre2.a is missing."
    archive = archives[0]

    listing = subprocess.run(["ar", "t", archive], capture_output=True, text=True)
    assert listing.returncode == 0 and listing.stdout.strip(), f"{archive} is not a valid nonempty archive."
    symbols = subprocess.run(["nm", "-C", archive], capture_output=True, text=True)
    assert symbols.returncode == 0 and "re2::RE2" in symbols.stdout, "libre2.a does not contain RE2 symbols."

    work = tempfile.mkdtemp(prefix="classifier-build-")
    obj = os.path.join(work, "classifier.o")
    rebuilt = os.path.join(work, "classifier")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-I/app/re2-src", "-c", SOURCE, "-o", obj],
        capture_output=True, text=True
    )
    assert compile_result.returncode == 0, f"log_classifier.cpp does not compile:\n{compile_result.stderr}"

    undefined = subprocess.run(["nm", "-C", "-u", obj], capture_output=True, text=True)
    assert undefined.returncode == 0
    assert "re2::RE2" in undefined.stdout, "log_classifier.cpp does not use the RE2 library API."

    link_result = subprocess.run(
        ["g++", obj, archive, "-pthread", "-o", rebuilt],
        capture_output=True, text=True
    )
    assert link_result.returncode == 0, f"Source cannot be linked against the compiled libre2.a:\n{link_result.stderr}"
    os.environ["REBUILT_CLASSIFIER"] = rebuilt


def test_classifier_accuracy():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus missing at {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    clean_modified = []

    for ef in evil_files:
        result = run_classifier(BINARY, ef)
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            evil_bypassed.append(os.path.basename(ef))

    for cf in clean_files:
        result = run_classifier(BINARY, cf)
        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            clean_modified.append(os.path.basename(cf))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def test_randomized_classifier_semantics():
    rebuilt = os.environ.get("REBUILT_CLASSIFIER")
    assert rebuilt and os.path.isfile(rebuilt), "Rebuilt classifier was not created."

    rng = random.SystemRandom()
    token = lambda: secrets.token_hex(rng.randrange(4, 15))
    cases = [
        f"user={token()} UNION {token()} SELECT {token()}",
        f"prefix SeLeCt {token()} FrOm suffix",
        f"request DROP {token()} TABLE accounts_{token()}",
        f"key=<ScRiPt data-x='{token()}'>alert(1)</sCrIpT>",
        f"url=JaVaScRiPt:{token()}()",
        f"image=x OnErRoR={token()}()",
        f"normal user={token()} key=ssh-rsa {token()}",
        f"mentions UNION and FROM but not the required ordering {token()}",
        f"SELECT without the other keyword {token()}",
        f"DROP\n{token()}\nTABLE",
        f"<script\n{token()}>not matched because dot does not cross newline",
        f"onerror = {token()}",
        f"java script:{token()}",
    ]
    for _ in range(35):
        choices = [
            f"{token()} union {token()} select {token()}",
            f"{token()} SELECT {token()} FROM {token()}",
            f"{token()} drop {token()} table {token()}",
            f"{token()} <script id={token()}> {token()}",
            f"{token()} javascript:{token()}",
            f"{token()} onerror={token()}",
            f"user={token()} key={token()}",
        ]
        cases.append(rng.choice(choices))
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="logs-") as directory:
        for content in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(content)
            expected_stdout, expected_code = expected_for(content)
            for executable in (BINARY, rebuilt):
                result = run_classifier(executable, path)
                assert result.returncode == expected_code, (
                    f"Wrong exit code for generated input: expected {expected_code}, got {result.returncode}"
                )
                assert result.stdout == expected_stdout + "\n", (
                    f"Wrong output for generated input: expected exactly {expected_stdout!r}"
                )


def test_task_complete_log_exists():
    log_path = "/home/user/task_complete.log"
    assert os.path.isfile(log_path), f"The file {log_path} is missing."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "CLASSIFIER READY" in content, f"Expected 'CLASSIFIER READY' in {log_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
