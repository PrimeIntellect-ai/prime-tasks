#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

EVIL_CORPUS_PATH = "/app/corpus/evil"
CLEAN_CORPUS_PATH = "/app/corpus/clean"
LIBRARY_DIR = "/app/libsecauth-1.0"
LIBRARY_PATH = os.path.join(LIBRARY_DIR, "libsecauth.so")
DETECTOR_PATH = "/home/user/detector"
DETECTOR_SOURCE = "/home/user/detector.c"


def detector_env():
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH")
    env["LD_LIBRARY_PATH"] = LIBRARY_DIR if not old else LIBRARY_DIR + ":" + old
    return env


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_check_library():
    clean = subprocess.run(
        ["make", "clean"], cwd=LIBRARY_DIR, capture_output=True, text=True, timeout=30
    )
    assert clean.returncode == 0, clean.stdout + clean.stderr

    build = subprocess.run(
        ["make"], cwd=LIBRARY_DIR, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(LIBRARY_PATH), "make did not produce libsecauth.so"

    dynamic = subprocess.run(
        ["readelf", "-d", LIBRARY_PATH], capture_output=True, text=True, timeout=10
    )
    assert dynamic.returncode == 0, dynamic.stderr
    assert re.search(r"Shared library: \[libcrypto(?:\.so[^]]*)?\]", dynamic.stdout), (
        "libsecauth.so is not dynamically linked to OpenSSL libcrypto"
    )


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector binary {DETECTOR_PATH} does not exist."
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector binary {DETECTOR_PATH} is not executable."


def test_detector_is_linked_program_using_secauth_api():
    assert os.path.isfile(DETECTOR_SOURCE), f"Detector source {DETECTOR_SOURCE} does not exist."
    source = open(DETECTOR_SOURCE, encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"](?:.*/)?secauth\.h[>\"]", source), (
        "detector.c does not include secauth.h"
    )
    assert re.search(r"\bsecauth_validate_token\s*\(", source), (
        "detector.c does not call secauth_validate_token"
    )

    header = subprocess.run(
        ["readelf", "-h", DETECTOR_PATH], capture_output=True, text=True, timeout=10
    )
    assert header.returncode == 0 and "ELF Header" in header.stdout, (
        "detector is not a compiled ELF program"
    )

    dynamic = subprocess.run(
        ["readelf", "-d", DETECTOR_PATH], capture_output=True, text=True, timeout=10
    )
    assert dynamic.returncode == 0, dynamic.stderr
    assert re.search(r"Shared library: \[libsecauth\.so\]", dynamic.stdout), (
        "detector is not dynamically linked against libsecauth.so"
    )

    symbols = subprocess.run(
        ["nm", "-D", DETECTOR_PATH], capture_output=True, text=True, timeout=10
    )
    assert symbols.returncode == 0, symbols.stderr
    assert re.search(r"\bU\s+secauth_validate_token(?:@\S+)?\s*$", symbols.stdout, re.MULTILINE), (
        "detector does not import secauth_validate_token from the shared library"
    )


def test_detector_against_corpus():
    env = detector_env()

    evil_files = [
        os.path.join(EVIL_CORPUS_PATH, f) for f in os.listdir(EVIL_CORPUS_PATH)
        if os.path.isfile(os.path.join(EVIL_CORPUS_PATH, f))
    ]
    clean_files = [
        os.path.join(CLEAN_CORPUS_PATH, f) for f in os.listdir(CLEAN_CORPUS_PATH)
        if os.path.isfile(os.path.join(CLEAN_CORPUS_PATH, f))
    ]

    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_PATH}."
    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_PATH}."

    evil_bypassed = []
    clean_modified = []

    for fpath in evil_files:
        result = subprocess.run(
            [DETECTOR_PATH, fpath], env=env, capture_output=True, text=True, timeout=10
        )
        if result.stdout.strip() != "REJECT":
            evil_bypassed.append(os.path.basename(fpath))

    for fpath in clean_files:
        result = subprocess.run(
            [DETECTOR_PATH, fpath], env=env, capture_output=True, text=True, timeout=10
        )
        if result.stdout.strip() != "ACCEPT":
            clean_modified.append(os.path.basename(fpath))

    error_messages = []
    if evil_bypassed:
        error_messages.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_modified:
        error_messages.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}"
        )
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_library_and_detector_on_fresh_random_tokens():
    lib = ctypes.CDLL(LIBRARY_PATH)
    validate = lib.secauth_validate_token
    validate.argtypes = [ctypes.c_char_p]
    validate.restype = ctypes.c_int

    nonce = secrets.token_hex(16)
    cases = [
        ("ECDSA", f"user={nonce}", "VALID_SIG", True),
        ("NONE", f"user={secrets.token_hex(16)}", "VALID_SIG", False),
        ("NONE", f"user={secrets.token_hex(16)}", secrets.token_hex(12), False),
        ("ECDSA", f"user={secrets.token_hex(16)}", secrets.token_hex(12), False),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="secauth-check-") as directory:
        for alg, data, sig, expected in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".tok")
            with open(path, "w", encoding="ascii") as token:
                token.write(f"ALG: {alg}\nDATA: {data}\nSIG: {sig}\n")

            library_result = validate(os.fsencode(path)) != 0
            assert library_result is expected, (
                f"libsecauth returned {library_result} for alg={alg}, sig={sig}"
            )

            result = subprocess.run(
                [DETECTOR_PATH, path],
                env=detector_env(),
                capture_output=True,
                text=True,
                timeout=10,
            )
            wanted = "ACCEPT" if expected else "REJECT"
            assert result.stdout.strip() == wanted, (
                f"detector printed {result.stdout.strip()!r}; expected {wanted}"
            )


def test_detector_output_is_driven_by_library_return_value():
    shim_source = r'''
#include <stdlib.h>
int secauth_validate_token(const char *filepath) {
    (void)filepath;
    const char *forced = getenv("SECAUTH_FORCED_RESULT");
    return forced && forced[0] == '1';
}
'''
    with tempfile.TemporaryDirectory(prefix="secauth-interpose-") as directory:
        source_path = os.path.join(directory, "shim.c")
        shim_path = os.path.join(directory, "shim.so")
        token_path = os.path.join(directory, secrets.token_hex(10) + ".tok")
        with open(source_path, "w", encoding="ascii") as f:
            f.write(shim_source)
        with open(token_path, "w", encoding="ascii") as f:
            f.write(f"ALG: ECDSA\nDATA: user={secrets.token_hex(12)}\nSIG: VALID_SIG\n")

        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", shim_path, source_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, compiled.stdout + compiled.stderr

        for forced, wanted in (("0", "REJECT"), ("1", "ACCEPT")):
            env = detector_env()
            env["LD_PRELOAD"] = shim_path
            env["SECAUTH_FORCED_RESULT"] = forced
            result = subprocess.run(
                [DETECTOR_PATH, token_path],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.stdout.strip() == wanted, (
                "detector output is not determined by secauth_validate_token's return value"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
