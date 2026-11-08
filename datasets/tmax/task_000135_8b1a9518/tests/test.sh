#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile
import urllib.request
import urllib.error
import time
import pytest

VALIDATOR_PATH = "/home/user/elf_validator"
SOURCE_PATH = "/home/user/elf_validator.c"
EVIL_CORPUS = "/app/corpus/evil/"
CLEAN_CORPUS = "/app/corpus/clean/"
NGINX_CONF = "/app/nginx/nginx.conf"

GENERATED_DIR = tempfile.mkdtemp(prefix="elf_cases_")


def _elf_layout(data):
    assert data[:4] == b"\x7fELF" and data[4] == 2, "Fresh compiler output was not ELF64"
    assert data[5] in (1, 2), "Unsupported ELF byte order"
    endian = "<" if data[5] == 1 else ">"
    phoff = struct.unpack_from(endian + "Q", data, 32)[0]
    phentsize = struct.unpack_from(endian + "H", data, 54)[0]
    phnum = struct.unpack_from(endian + "H", data, 56)[0]
    assert phentsize >= 56
    assert phoff + phentsize * phnum <= len(data)
    return endian, phoff, phentsize, phnum


def _make_generated_cases():
    token = secrets.token_hex(12)
    source = os.path.join(GENERATED_DIR, token + ".c")
    baseline = os.path.join(GENERATED_DIR, token + "_base")
    with open(source, "w") as f:
        f.write("#include <stdint.h>\n"
                "volatile uint64_t marker = UINT64_C(0x%s);\n"
                "int main(void) { return marker == 0; }\n" % secrets.token_hex(8))
    subprocess.run(["gcc", source, "-o", baseline], check=True, capture_output=True)

    with open(baseline, "rb") as f:
        original = bytearray(f.read())
    endian, phoff, phentsize, phnum = _elf_layout(original)

    stack_header = None
    dynamic_header = None
    for index in range(phnum):
        off = phoff + index * phentsize
        p_type = struct.unpack_from(endian + "I", original, off)[0]
        if p_type == 0x6474E551:
            stack_header = off
        elif p_type == 2:
            dynamic_header = off

    assert stack_header is not None, "Fresh compiler output lacks PT_GNU_STACK"
    assert dynamic_header is not None, "Fresh compiler output lacks PT_DYNAMIC"
    assert struct.unpack_from(endian + "I", original, stack_header + 4)[0] & 1 == 0

    dyn_offset = struct.unpack_from(endian + "Q", original, dynamic_header + 8)[0]
    dyn_size = struct.unpack_from(endian + "Q", original, dynamic_header + 32)[0]
    assert dyn_offset + dyn_size <= len(original) and dyn_size >= 16

    null_entry = None
    for off in range(dyn_offset, dyn_offset + dyn_size, 16):
        tag = struct.unpack_from(endian + "q", original, off)[0]
        assert tag not in (15, 29), "Fresh baseline unexpectedly contains RPATH/RUNPATH"
        if tag == 0 and null_entry is None:
            null_entry = off
    assert null_entry is not None, "Fresh dynamic table has no DT_NULL slot"

    cases = []

    def save(label, data, expected):
        path = os.path.join(GENERATED_DIR, secrets.token_hex(10) + "_" + label)
        with open(path, "wb") as f:
            f.write(data)
        cases.append((path, expected, label))

    # Appended random bytes are outside all ELF structures and keep these files valid.
    save("clean_a.elf", original + secrets.token_bytes(37), 0)
    save("clean_b.elf", original + secrets.token_bytes(83), 0)

    bad_magic = bytearray(original)
    bad_magic[0:4] = secrets.token_bytes(4)
    while bad_magic[0:4] == b"\x7fELF":
        bad_magic[0:4] = secrets.token_bytes(4)
    save("bad_magic.elf", bad_magic, 1)

    wrong_class = bytearray(original)
    wrong_class[4] = 1
    save("elf32_class.elf", wrong_class, 1)

    exec_stack = bytearray(original)
    flags = struct.unpack_from(endian + "I", exec_stack, stack_header + 4)[0]
    struct.pack_into(endian + "I", exec_stack, stack_header + 4, flags | 1)
    save("exec_stack.elf", exec_stack, 1)

    rpath = bytearray(original)
    struct.pack_into(endian + "q", rpath, null_entry, 15)
    struct.pack_into(endian + "Q", rpath, null_entry + 8, 0)
    save("rpath.elf", rpath, 1)

    runpath = bytearray(original)
    struct.pack_into(endian + "q", runpath, null_entry, 29)
    struct.pack_into(endian + "Q", runpath, null_entry + 8, 0)
    save("runpath.elf", runpath, 1)

    save("truncated.elf", original[:32], 1)
    return cases


GENERATED_CASES = _make_generated_cases()


def _exercise_validator(executable):
    cases = list(GENERATED_CASES)
    secrets.SystemRandom().shuffle(cases)
    failures = []
    for path, expected, label in cases:
        result = subprocess.run([executable, path], capture_output=True, timeout=5)
        if result.returncode != expected:
            failures.append(f"{label}: expected {expected}, got {result.returncode}")
    assert not failures, "Generated ELF evaluation failed: " + " | ".join(failures)


def test_elf_validator_exists_and_executable():
    assert os.path.isfile(VALIDATOR_PATH), f"Validator binary not found at {VALIDATOR_PATH}"
    assert os.access(VALIDATOR_PATH, os.X_OK), f"Validator binary at {VALIDATOR_PATH} is not executable"
    with open(VALIDATOR_PATH, "rb") as f:
        ident = f.read(5)
    assert ident[:4] == b"\x7fELF" and ident[4] == 2, "Validator must be a compiled 64-bit ELF executable"


def test_validator_source_exists_is_c_and_rebuilds():
    assert os.path.isfile(SOURCE_PATH), f"Validator source not found at {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", errors="replace") as f:
        source = f.read()
    assert source.strip(), "Validator C source is empty"

    # Remove comments and literals before checking for calls that delegate parsing
    # to external programs.
    lexical = re.sub(
        r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        ' ', source, flags=re.S)
    forbidden = re.compile(
        r'\b(?:system|popen|fork|vfork|execl|execlp|execle|execv|execvp|execvpe|execve|posix_spawn|posix_spawnp)\s*\(')
    match = forbidden.search(lexical)
    assert match is None, f"Validator source delegates work through forbidden call {match.group(0) if match else ''}"

    rebuilt = os.path.join(GENERATED_DIR, "rebuilt_" + secrets.token_hex(10))
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE_PATH, "-o", rebuilt],
        capture_output=True, text=True)
    assert result.returncode == 0, "elf_validator.c does not compile:\n" + result.stderr
    _exercise_validator(rebuilt)


def test_generated_unpredictable_elf_evaluation():
    _exercise_validator(VALIDATOR_PATH)


def test_corpus_evaluation():
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]

    assert len(evil_files) > 0, "No files found in evil corpus"
    assert len(clean_files) > 0, "No files found in clean corpus"

    evil_bypassed = []
    for ef in evil_files:
        result = subprocess.run([VALIDATOR_PATH, ef], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(ef))

    clean_modified = []
    for cf in clean_files:
        result = subprocess.run([VALIDATOR_PATH, cf], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(cf))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")

    if error_msg:
        pytest.fail("Corpus evaluation failed. " + " | ".join(error_msg))


def test_nginx_config_updated():
    with open(NGINX_CONF, 'r') as f:
        content = f.read()

    assert "Content-Security-Policy" in content, "CSP header missing in Nginx config"
    assert "default-src 'none'" in content and "frame-ancestors 'none'" in content, "CSP header values are incorrect"
    assert "proxy_pass http://127.0.0.1:9090" in content.replace(" ", "").replace("\t", "").replace("proxy_passhttp://127.0.0.1:9090", "proxy_pass http://127.0.0.1:9090"), "proxy_pass to backend missing in Nginx config"


def test_end_to_end_flow():
    subprocess.run(["/app/start_services.sh"], check=False)
    time.sleep(2)

    clean_sample = next(path for path, expected, label in GENERATED_CASES if expected == 0)
    evil_candidates = [(path, label) for path, expected, label in GENERATED_CASES if expected == 1]
    evil_sample, _ = secrets.choice(evil_candidates)

    with open(clean_sample, 'rb') as f:
        clean_data = f.read()
    with open(evil_sample, 'rb') as f:
        evil_data = f.read()

    req_clean = urllib.request.Request("http://127.0.0.1:8080/upload", data=clean_data, method="POST")
    try:
        with urllib.request.urlopen(req_clean, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 for clean binary, got {response.status}"
            csp = response.getheader("Content-Security-Policy")
            assert csp is not None, "Content-Security-Policy header is missing in response"
            assert "default-src 'none'" in csp and "frame-ancestors 'none'" in csp, "CSP header in response is incorrect"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Expected HTTP 200 for clean binary, got {e.code}")
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx for clean binary: {e}")

    req_evil = urllib.request.Request("http://127.0.0.1:8080/upload", data=evil_data, method="POST")
    try:
        with urllib.request.urlopen(req_evil, timeout=5) as response:
            pytest.fail(f"Expected HTTP 400 for evil binary, got {response.status}")
    except urllib.error.HTTPError as e:
        assert e.code == 400, f"Expected HTTP 400 for evil binary, got {e.code}"
        csp = e.headers.get("Content-Security-Policy")
        assert csp is not None, "Content-Security-Policy header is missing in 400 response"
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx for evil binary: {e}")

    try:
        redis_result = subprocess.run(["redis-cli", "dbsize"], capture_output=True, text=True, timeout=3)
        assert redis_result.returncode == 0, "Failed to connect to Redis"
        keys_count = int(redis_result.stdout.strip().split('\n')[-1])
        assert keys_count > 0, "No audit logs found in Redis"
    except Exception as e:
        pytest.fail(f"Redis validation failed: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
