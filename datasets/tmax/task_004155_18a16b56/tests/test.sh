#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import re
import subprocess
import tempfile
import uuid
import pytest

SAFEGUARD_SCRIPT = "/home/user/safeguard.sh"
EVIL_CORPUS = "/home/user/corpus/evil"
CLEAN_CORPUS = "/home/user/corpus/clean"

DEP_RE = re.compile(rb"DEP [A-Za-z0-9.-]+ [A-Za-z0-9.-]+")
FFI_RE = re.compile(rb"FFI_BIND /[A-Za-z0-9/.-]*")

def test_safeguard_exists_and_executable():
    assert os.path.isfile(SAFEGUARD_SCRIPT), f"Safeguard script is missing: {SAFEGUARD_SCRIPT}"
    assert os.access(SAFEGUARD_SCRIPT, os.X_OK), f"Safeguard script is not executable: {SAFEGUARD_SCRIPT}"

def test_safeguard_is_bash_script():
    with open(SAFEGUARD_SCRIPT, "rb") as f:
        first_line = f.readline(256)
    assert re.match(rb"^#![^\n]*\bbash(?:\s|$)", first_line), "Safeguard must be a Bash script"

def test_clean_corpus_accepted():
    if not os.path.isfile(SAFGUARD_SCRIPT):
        pytest.fail("Safeguard script does not exist.")

    failures = []
    files = [f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    total = len(files)

    for f in files:
        path = os.path.join(CLEAN_CORPUS, f)
        res = subprocess.run([SAFEGUARD_SCRIPT, path], capture_output=True, text=True)
        out = res.stdout.strip()

        if res.returncode != 0 or out != "ACCEPT":
            failures.append(f)

    if failures:
        pytest.fail(f"{len(failures)} of {total} clean files rejected or improperly handled. Offending files: {', '.join(failures)}")

def test_evil_corpus_rejected():
    if not os.path.isfile(SAFEGUARD_SCRIPT):
        pytest.fail("Safeguard script does not exist.")

    failures = []
    files = [f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    total = len(files)

    for f in files:
        path = os.path.join(EVIL_CORPUS, f)
        res = subprocess.run([SAFEGUARD_SCRIPT, path], capture_output=True, text=True)
        out = res.stdout.strip()

        if res.returncode != 1 or out != "REJECT":
            failures.append(f)

    if failures:
        pytest.fail(f"{len(failures)} of {total} evil files bypassed validation. Offending files: {', '.join(failures)}")

def grammar_valid(data):
    if b"\r" in data:
        return False
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    if len(lines) < 4 or lines[0] != b"BEGIN_ARTIFACT" or lines[-1] != b"END_ARTIFACT":
        return False

    i = 1
    dep_count = 0
    while i < len(lines) - 1 and DEP_RE.fullmatch(lines[i]):
        dep_count += 1
        i += 1
    if dep_count == 0 or i != len(lines) - 2 or not FFI_RE.fullmatch(lines[i]):
        return False

    path = lines[i][len(b"FFI_BIND "):]
    if any(component == b".." for component in path.split(b"/")):
        return False
    return True

def run_generated_case(path, expected):
    try:
        res = subprocess.run([SAFEGUARD_SCRIPT, path], capture_output=True, timeout=3)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Safeguard timed out on generated input {path}")
    expected_code = 0 if expected else 1
    expected_word = b"ACCEPT" if expected else b"REJECT"
    assert res.returncode == expected_code, f"Wrong exit code for generated input {path}"
    assert res.stdout in (expected_word, expected_word + b"\n"), f"Wrong or extra stdout for generated input {path}: {res.stdout!r}"

def test_generated_descriptors_against_independent_grammar():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    def token():
        parts = []
        for _ in range(rng.randint(1, 4)):
            parts.append("".join(rng.choice(alphabet) for _ in range(rng.randint(1, 8))))
        return rng.choice(["-", "."]).join(parts)

    def valid_descriptor():
        deps = [f"DEP {token()} {token()}" for _ in range(rng.randint(1, 5))]
        segments = [token() for _ in range(rng.randint(1, 5))]
        header = "/" + "/".join(segments)
        return ("\n".join(["BEGIN_ARTIFACT", *deps, f"FFI_BIND {header}", "END_ARTIFACT"]) + rng.choice(["", "\n"])).encode()

    candidates = [valid_descriptor() for _ in range(35)]
    base = valid_descriptor().rstrip(b"\n").split(b"\n")
    candidates.extend([
        b"",
        b"BEGIN_ARTIFACT\nFFI_BIND /usr/include/a.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nEND_ARTIFACT\n",
        b"WRONG_BEGIN\nDEP pkg 1.0\nFFI_BIND /a/b.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND /a/b.h\nWRONG_END\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND relative/path.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND /a/../secret\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND /a/%2e%2e/secret\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP bad$name 1.0\nFFI_BIND /a/b.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1;cmd\nFFI_BIND /a/b.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP  pkg 1.0\nFFI_BIND /a/b.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0 extra\nFFI_BIND /a/b.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND /a/b.h;cmd\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND /a/b.h\nFFI_BIND /c/d.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nFFI_BIND /a/b.h\nDEP pkg 1.0\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND /a/b.h\nEND_ARTIFACT\nEXTRA\n",
        b"BEGIN_ARTIFACT\n\nDEP pkg 1.0\nFFI_BIND /a/b.h\nEND_ARTIFACT\n",
        b"BEGIN_ARTIFACT\r\nDEP pkg 1.0\r\nFFI_BIND /a/b.h\r\nEND_ARTIFACT\r\n",
        b"\n".join(base[:-1]),
    ])

    random_lines = [
        b"BEGIN_ARTIFACT", b"END_ARTIFACT", b"FFI_BIND /tmp/a.h",
        b"FFI_BIND /tmp/../x", b"DEP pkg 1.0", b"DEP bad$name 2.0",
        b"", b"EXTRA", b"FFI_BIND relative.h",
    ]
    for _ in range(70):
        lines = [rng.choice(random_lines) for _ in range(rng.randint(0, 8))]
        candidates.append(b"\n".join(lines) + rng.choice([b"", b"\n"]))

    expected = [grammar_valid(data) for data in candidates]
    assert any(expected) and not all(expected), "Generated suite must contain valid and invalid descriptors"

    order = list(range(len(candidates)))
    rng.shuffle(order)
    with tempfile.TemporaryDirectory(prefix="descriptor-validation-") as td:
        for index in order:
            path = os.path.join(td, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(candidates[index])
            run_generated_case(path, expected[index])

def test_argument_count_and_missing_file_rejected():
    invocations = [
        [SAFEGUARD_SCRIPT],
        [SAFEGUARD_SCRIPT, "/definitely/not/a/descriptor"],
    ]
    with tempfile.NamedTemporaryFile() as f:
        f.write(b"BEGIN_ARTIFACT\nDEP pkg 1.0\nFFI_BIND /a/b.h\nEND_ARTIFACT\n")
        f.flush()
        invocations.append([SAFEGUARD_SCRIPT, f.name, f.name])
        for command in invocations:
            res = subprocess.run(command, capture_output=True, timeout=3)
            assert res.returncode == 1
            assert res.stdout in (b"REJECT", b"REJECT\n")
TEST_EOF

# Correct a typo only in the copied existence guard while retaining its assertion.
sed -i 's/SAFGUARD_SCRIPT/SAFEGUARD_SCRIPT/g' /tmp/test_final_state.py

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
