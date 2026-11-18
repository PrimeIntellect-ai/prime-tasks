#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tempfile

import pytest

DETECT_SCRIPT = "/home/user/detect.sh"
LIB_DIR = "/app/libtokenparse-1.0"
SOURCE = os.path.join(LIB_DIR, "tokenparse.c")
MAKEFILE = os.path.join(LIB_DIR, "Makefile")
VERIFY_TOKEN = os.path.join(LIB_DIR, "verify_token")
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, timeout=5, **kwargs)


@pytest.fixture(scope="session", autouse=True)
def build_and_compile_source():
    assert os.path.isfile(SOURCE), f"Missing parser source: {SOURCE}"
    assert os.path.isfile(MAKEFILE), f"Missing Makefile: {MAKEFILE}"

    if os.path.lexists(VERIFY_TOKEN):
        os.remove(VERIFY_TOKEN)
    built = run(["make", "-B", "verify_token"], cwd=LIB_DIR)
    assert built.returncode == 0, (
        "The repaired Makefile failed to build verify_token.\n"
        + built.stdout.decode(errors="replace")
        + built.stderr.decode(errors="replace")
    )
    assert os.path.isfile(VERIFY_TOKEN), "make did not create verify_token"
    assert os.access(VERIFY_TOKEN, os.X_OK), "verify_token is not executable"
    with open(VERIFY_TOKEN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "verify_token is not a compiled ELF executable"

    with tempfile.TemporaryDirectory(prefix="source-build-") as td:
        source_binary = os.path.join(td, "verify_token_from_source")
        compiled = run(["gcc", "-O0", "-o", source_binary, SOURCE])
        assert compiled.returncode == 0, (
            "tokenparse.c does not compile independently.\n"
            + compiled.stdout.decode(errors="replace")
            + compiled.stderr.decode(errors="replace")
        )
        yield source_binary


def write_token(directory, declared_length, payload):
    path = os.path.join(directory, secrets.token_hex(12) + ".bin")
    with open(path, "wb") as f:
        f.write(struct.pack("<H", declared_length))
        f.write(payload)
    return path


def assert_parser_result(binary, path, expected):
    result = run([binary, path])
    assert result.returncode == expected, (
        f"{binary} returned {result.returncode} for a token expected to return {expected}"
    )


def test_detect_script_exists_and_executable():
    assert os.path.isfile(DETECT_SCRIPT), f"The script {DETECT_SCRIPT} does not exist."
    assert os.access(DETECT_SCRIPT, os.X_OK), f"The script {DETECT_SCRIPT} is not executable."


def test_verify_token_argument_validation():
    assert run([VERIFY_TOKEN]).returncode != 0
    assert run([VERIFY_TOKEN, "/definitely/missing/token", "/another/argument"]).returncode != 0
    assert run([VERIFY_TOKEN, "/definitely/missing/token"]).returncode != 0


def test_repaired_source_and_built_tool_on_generated_tokens(build_and_compile_source):
    source_binary = build_and_compile_source
    with tempfile.TemporaryDirectory(prefix="parser-cases-") as td:
        clean = []
        evil = []

        for length in [0, 1, 2, 17, 127, 255, 256]:
            clean.append(write_token(td, length, os.urandom(length)))
        for _ in range(6):
            length = secrets.randbelow(255) + 1
            clean.append(write_token(td, length, os.urandom(length)))

        for length in [257, 300, 511, 700]:
            evil.append(write_token(td, length, os.urandom(length)))
        for _ in range(6):
            length = secrets.randbelow(443) + 257
            evil.append(write_token(td, length, os.urandom(length)))

        for binary in (source_binary, VERIFY_TOKEN):
            for path in clean:
                assert_parser_result(binary, path, 0)
            for path in evil:
                assert_parser_result(binary, path, 1)


def test_detector_on_generated_unpredictable_paths():
    with tempfile.TemporaryDirectory(prefix="detector-cases-") as td:
        cases = []
        for _ in range(10):
            length = secrets.randbelow(257)
            cases.append((write_token(td, length, os.urandom(length)), 0))
        for _ in range(10):
            length = secrets.randbelow(443) + 257
            cases.append((write_token(td, length, os.urandom(length)), 1))

        for path, expected in cases:
            result = run([DETECT_SCRIPT, path])
            assert result.returncode == expected, (
                f"detect.sh returned {result.returncode} for generated token {path}; expected {expected}"
            )


def test_detect_argument_validation():
    assert run([DETECT_SCRIPT]).returncode != 0
    assert run([DETECT_SCRIPT, "/tmp/one", "/tmp/two"]).returncode != 0

    with tempfile.TemporaryDirectory(prefix="relative-token-") as td:
        name = "relative.bin"
        with open(os.path.join(td, name), "wb") as f:
            f.write(struct.pack("<H", 1) + b"X")
        assert run([DETECT_SCRIPT, name], cwd=td).returncode != 0


def test_adversarial_corpus():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}."
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}."

    clean_failed = []
    for cf in clean_files:
        result = subprocess.run([DETECT_SCRIPT, cf], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        result = subprocess.run([DETECT_SCRIPT, ef], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")

    assert not errors, "Adversarial corpus validation failed:\n" + "\n".join(errors)


def test_detector_actually_uses_verify_token():
    probe_source = r'''#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    const char *log = getenv("PROBE_LOG");
    const char *code = getenv("PROBE_EXIT");
    if (log) {
        FILE *f = fopen(log, "w");
        if (f) {
            fprintf(f, "%d\n%s\n", argc - 1, argc > 1 ? argv[1] : "");
            fclose(f);
        }
    }
    return code ? atoi(code) : 99;
}
'''
    with tempfile.TemporaryDirectory(prefix="verify-probe-") as td:
        probe_c = os.path.join(td, "probe.c")
        probe_bin = os.path.join(td, "probe")
        backup = os.path.join(td, "real_verify_token")
        log = os.path.join(td, "probe.log")
        with open(probe_c, "w") as f:
            f.write(probe_source)
        compiled = run(["gcc", "-O2", "-o", probe_bin, probe_c])
        assert compiled.returncode == 0
        shutil.copy2(VERIFY_TOKEN, backup)

        clean_path = write_token(td, 8, os.urandom(8))
        evil_path = write_token(td, 300, os.urandom(300))
        try:
            shutil.copy2(probe_bin, VERIFY_TOKEN)
            os.chmod(VERIFY_TOKEN, 0o755)

            env = os.environ.copy()
            env.update({"PROBE_LOG": log, "PROBE_EXIT": "1"})
            result = run([DETECT_SCRIPT, clean_path], env=env)
            assert result.returncode == 1, "detect.sh ignored verify_token's rejection"
            assert os.path.isfile(log), "detect.sh did not invoke /app/libtokenparse-1.0/verify_token"
            with open(log) as f:
                lines = f.read().splitlines()
            assert lines == ["1", clean_path], "detect.sh did not pass exactly the requested path to verify_token"

            os.remove(log)
            env.update({"PROBE_EXIT": "0"})
            result = run([DETECT_SCRIPT, evil_path], env=env)
            assert result.returncode == 0, "detect.sh classified independently instead of using verify_token"
            assert os.path.isfile(log), "detect.sh did not invoke verify_token on the second probe"
            with open(log) as f:
                lines = f.read().splitlines()
            assert lines == ["1", evil_path]
        finally:
            shutil.copy2(backup, VERIFY_TOKEN)
            os.chmod(VERIFY_TOKEN, 0o755)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
