#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

BINARY_PATH = "/home/user/waf_filter/target/release/waf_filter"
PROJECT_DIR = Path("/home/user/waf_filter")
NORMALIZE_C = Path("/app/libnormalize/normalize.c")
CLEAN_CORPUS_DIR = "/app/verifier_corpus/clean"
EVIL_CORPUS_DIR = "/app/verifier_corpus/evil"


def run_build():
    subprocess.run(["cargo", "clean"], cwd=PROJECT_DIR, check=True, timeout=120,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    result = subprocess.run(["cargo", "build", "--release"], cwd=PROJECT_DIR,
                            timeout=240, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True)
    assert result.returncode == 0, f"Release build failed:\n{result.stdout}\n{result.stderr}"


@pytest.fixture(scope="session", autouse=True)
def rebuild_submission():
    assert PROJECT_DIR.is_dir(), f"Project missing: {PROJECT_DIR}"
    run_build()


def run_input(content):
    directory = tempfile.mkdtemp(prefix="waf_case_" + uuid.uuid4().hex + "_")
    path = os.path.join(directory, uuid.uuid4().hex + ".txt")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    return subprocess.run([BINARY_PATH, path], capture_output=True, timeout=10).returncode


def expected_status(content):
    normalized = content.replace("\u200b", "").lower()
    return 1 if ("or 1=1" in normalized or "bloodhound" in normalized) else 0


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (should be accepted/exit 0): {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be rejected/exit 1): {', '.join(failed_files)}")


def test_build_rs_and_ffi_are_present():
    build_rs = PROJECT_DIR / "build.rs"
    cargo_toml = PROJECT_DIR / "Cargo.toml"
    assert build_rs.is_file(), "build.rs is missing"
    assert cargo_toml.is_file(), "Cargo.toml is missing"

    build_text = build_rs.read_text(encoding="utf-8", errors="replace")
    assert "normalize.c" in build_text, "build.rs does not compile normalize.c"
    assert ("cc::Build" in build_text or
            re.search(r"Command\s*::\s*new\s*\(\s*['\"](?:gcc|cc)['\"]", build_text) or
            "rustc-link-lib" in build_text), "build.rs does not appear to compile/link the C library"

    rust_sources = []
    source_dir = PROJECT_DIR / "src"
    if source_dir.is_dir():
        rust_sources = list(source_dir.rglob("*.rs"))
    assert rust_sources, "Rust source files are missing"
    source_text = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in rust_sources)
    assert re.search(r'extern\s*"C"', source_text), "Rust source has no C extern block"
    assert len(re.findall(r"\bnormalize_text\b", source_text)) >= 2, "normalize_text is not declared and called through FFI"


def test_randomized_content_and_normalization():
    nonce = uuid.uuid4().hex
    cases = [
        f"ordinary benign message {nonce}",
        f"OR 1 = 1 is spaced and benign {nonce}",
        f"blood hound is two words {nonce}",
        f"prefix OR 1=1 suffix {nonce}",
        f"prefix O\u200bR 1=1 suffix {nonce}",
        f"prefix BLOODHOUND suffix {nonce}",
        f"prefix bl\u200boodhound suffix {nonce}",
        f"unrelated SQL: select 1 from records {nonce}",
    ]
    for content in cases:
        actual = run_input(content)
        expected = expected_status(content)
        assert actual == expected, f"Wrong exit status for generated input: expected {expected}, got {actual}"


def test_binary_really_uses_compiled_c_normalizer():
    token = "ffiprobe" + uuid.uuid4().hex
    assert run_input(token) == 0, "Random benign FFI probe was rejected before instrumentation"

    original = NORMALIZE_C.read_bytes()
    instrumented = f'''#include <string.h>
void normalize_text(char* input) {{
    int j = 0;
    for (int i = 0; input[i] != '\\0'; i++) {{
        if ((unsigned char)input[i] == 0xE2 && (unsigned char)input[i+1] == 0x80 && (unsigned char)input[i+2] == 0x8B) {{
            i += 2;
            continue;
        }}
        if (input[i] >= 'A' && input[i] <= 'Z') input[j++] = input[i] + 32;
        else input[j++] = input[i];
    }}
    input[j] = '\\0';
    if (strstr(input, "{token}") != 0) strcpy(input, "bloodhound");
}}
'''.encode("utf-8")

    try:
        NORMALIZE_C.write_bytes(instrumented)
        run_build()
        assert run_input(token) == 1, "Rebuilt binary did not use normalize_text from the C library"
    finally:
        NORMALIZE_C.write_bytes(original)
        run_build()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
