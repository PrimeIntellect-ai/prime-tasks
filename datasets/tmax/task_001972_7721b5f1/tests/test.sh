#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import math
import os
import random
import re
import shutil
import string
import struct
import subprocess
import tempfile

import pytest

CLASSIFIER = "/home/user/classifier.py"
LIBRARY = "/app/build/libartifact.so"
SOURCE = "/app/src/artifact_parser.cpp"


def run_classifier(path, timeout=10):
    result = subprocess.run(
        ["python3", CLASSIFIER, path],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, result.stderr
    assert result.stderr == "", f"Classifier wrote to stderr: {result.stderr!r}"
    output = result.stdout.strip()
    assert output in {"CLEAN", "EVIL"}, f"Unexpected classifier output: {result.stdout!r}"
    return output


def neutral_artifact(data):
    directory = tempfile.mkdtemp(prefix="artifact_check_")
    name = "item_" + "".join(random.choice(string.ascii_letters) for _ in range(20)) + ".bin"
    path = os.path.join(directory, name)
    with open(path, "wb") as handle:
        handle.write(data)
    return directory, path


def call_library(data):
    encoded = base64.b64encode(data).decode("ascii")
    code = r'''
import base64, ctypes, sys
payload = base64.b64decode(sys.argv[1])
lib = ctypes.CDLL("/app/build/libartifact.so")
fn = lib.parse_artifact
fn.argtypes = [ctypes.c_void_p, ctypes.c_int]
fn.restype = ctypes.c_int
buf = ctypes.create_string_buffer(payload, len(payload) + 1)
print(fn(buf, len(payload)))
'''
    result = subprocess.run(
        ["python3", "-c", code, encoded], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Library crashed or failed to load: {result.stderr}"
    return int(result.stdout.strip())


def test_classifier_exists():
    assert os.path.isfile(CLASSIFIER), "Classifier script is missing at /home/user/classifier.py"


def test_shared_library_exists_and_loads():
    assert os.path.isfile(LIBRARY), "Shared library is missing at /app/build/libartifact.so"
    with open(LIBRARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "libartifact.so is not an ELF shared library"
    lib = ctypes.CDLL(LIBRARY)
    assert getattr(lib, "parse_artifact", None) is not None, "parse_artifact is not exported"


def test_source_and_build_files_are_patched():
    assert os.path.isfile(SOURCE), "artifact_parser.cpp is missing"
    source = open(SOURCE, encoding="utf-8", errors="replace").read()
    assert "__MAGIC_1__" not in source and "__MAGIC_2__" not in source and "__MAX_BUF__" not in source
    assert not re.search(r"\b(strcpy|strcat|gets)\s*\(", source), "An explicitly unsafe string function remains"
    if re.search(r"\bmalloc\s*\(", source):
        assert re.search(r"\bfree\s*\(", source), "malloc is still used without any corresponding free"
    makefiles = []
    for root, dirs, files in os.walk("/app"):
        dirs[:] = [d for d in dirs if d not in {"corpora", "build"}]
        if "Makefile" in files or "makefile" in files:
            makefiles.append(root)
    assert makefiles, "No Makefile was created under /app"


def test_library_behavior_and_boundaries():
    clean = b"440\n880\n" + b"A" * (1320 - 8)
    bad_cases = [
        b"441\n880\n" + b"A" * 40,
        b"440\n881\n" + b"A" * 40,
        b"440\n880\nEXEC_PAYLOAD",
        b"440\n880\nA\x00EXEC_PAYLOAD",
        b"440\n880\n" + b"A" * (1321 - 8),
    ]
    clean_result = call_library(clean)
    short_clean_result = call_library(b"440\n880\nordinary data")
    assert clean_result == short_clean_result, "Valid artifacts do not produce a consistent parser result"
    for payload in bad_cases:
        assert call_library(payload) != clean_result, "The C++ parser failed to reject a malicious artifact"


def test_classifier_on_unlabeled_generated_inputs():
    cases = [
        (b"440\n880\n" + os.urandom(73), "CLEAN"),
        (b"440\n880\n" + b"B" * (1320 - 8), "CLEAN"),
        (b"439\n880\n" + b"C" * 27, "EVIL"),
        (b"440\n879\n" + b"D" * 27, "EVIL"),
        (b"440\n880\nprefix_EXEC_PAYLOAD_suffix", "EVIL"),
        (b"440\n880\nA\x00EXEC_PAYLOAD", "EVIL"),
        (b"440\n880\n" + b"E" * (1321 - 8), "EVIL"),
    ]
    for payload, expected in cases:
        directory, path = neutral_artifact(payload)
        try:
            assert run_classifier(path) == expected
        finally:
            shutil.rmtree(directory)


def test_classifier_really_calls_library_with_file_content():
    clean_result = call_library(b"440\n880\nprobe clean")
    evil_result = call_library(b"440\n880\nEXEC_PAYLOAD")
    assert clean_result != evil_result

    token = "".join(random.choice(string.ascii_letters) for _ in range(24))
    trace = f"/tmp/libartifact_trace_{token}"
    backup = f"/tmp/libartifact_backup_{token}.so"
    probe_cpp = f"/tmp/libartifact_probe_{token}.cpp"
    probe_so = f"/tmp/libartifact_probe_{token}.so"
    source = r'''
#include <cstdint>
#include <cstring>
#include <fstream>
extern "C" int parse_artifact(const char* data, int length) {
    std::ofstream out("TRACE_PATH", std::ios::binary | std::ios::app);
    uint32_t n = length < 0 ? 0U : static_cast<uint32_t>(length);
    out.write(reinterpret_cast<const char*>(&n), sizeof(n));
    if (length > 0 && data) out.write(data, length);
    out.close();
    bool bad = !data || length < 8 || length > 1320;
    if (!bad) {
        bad = std::memcmp(data, "440\n880\n", 8) != 0;
        const char needle[] = "EXEC_PAYLOAD";
        for (int i = 0; !bad && i + 12 <= length; ++i)
            if (std::memcmp(data + i, needle, 12) == 0) bad = true;
    }
    return bad ? EVIL_RESULT : CLEAN_RESULT;
}
'''.replace("TRACE_PATH", trace).replace("CLEAN_RESULT", str(clean_result)).replace("EVIL_RESULT", str(evil_result))
    with open(probe_cpp, "w") as handle:
        handle.write(source)
    built = subprocess.run(
        ["g++", "-shared", "-fPIC", "-O2", probe_cpp, "-o", probe_so],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert built.returncode == 0, built.stderr

    payload = b"440\n880\n" + os.urandom(91)
    directory, path = neutral_artifact(payload)
    shutil.copy2(LIBRARY, backup)
    try:
        os.replace(probe_so, LIBRARY)
        assert run_classifier(path) == "CLEAN"
        assert os.path.isfile(trace), "Classifier did not call parse_artifact in /app/build/libartifact.so"
        raw = open(trace, "rb").read()
        records = []
        offset = 0
        while offset + 4 <= len(raw):
            size = struct.unpack_from("I", raw, offset)[0]
            offset += 4
            assert offset + size <= len(raw), "Malformed parser-call trace"
            records.append(raw[offset:offset + size])
            offset += size
        assert offset == len(raw)
        assert payload in records, "Classifier did not pass the complete file content to the C++ parser"
    finally:
        shutil.copy2(backup, LIBRARY)
        shutil.rmtree(directory)
        for path_to_remove in (backup, probe_cpp, probe_so, trace):
            try:
                os.remove(path_to_remove)
            except FileNotFoundError:
                pass


def test_benchmark_log_exists_and_is_valid():
    path = "/home/user/benchmark.log"
    assert os.path.isfile(path), "Benchmark log is missing at /home/user/benchmark.log"
    text = open(path, encoding="utf-8").read()
    match = re.fullmatch(r"Throughput: ([0-9]+(?:\.[0-9]+)?) MB/s\n?", text)
    assert match, "benchmark.log must have the format 'Throughput: <value> MB/s'"
    value = float(match.group(1))
    assert math.isfinite(value) and value > 0, "Benchmark throughput must be a positive finite value"
    ten_mb_files = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            candidate = os.path.join(root, name)
            try:
                if os.path.isfile(candidate) and os.path.getsize(candidate) == 10 * 1024 * 1024:
                    ten_mb_files.append(candidate)
            except OSError:
                pass
    assert ten_mb_files, "No exactly 10 MiB dummy benchmark file was created under /home/user"


def test_adversarial_corpus():
    evil_corpus_path = "/app/corpora/evil/"
    clean_corpus_path = "/app/corpora/clean/"
    assert os.path.isdir(evil_corpus_path), f"Evil corpus path {evil_corpus_path} does not exist."
    assert os.path.isdir(clean_corpus_path), f"Clean corpus path {clean_corpus_path} does not exist."
    evil_files = [os.path.join(evil_corpus_path, f) for f in os.listdir(evil_corpus_path) if os.path.isfile(os.path.join(evil_corpus_path, f))]
    clean_files = [os.path.join(clean_corpus_path, f) for f in os.listdir(clean_corpus_path) if os.path.isfile(os.path.join(clean_corpus_path, f))]
    evil_failures = []
    for filepath in evil_files:
        try:
            output = run_classifier(filepath, 5)
            if output != "EVIL":
                evil_failures.append((os.path.basename(filepath), output))
        except Exception as exc:
            evil_failures.append((os.path.basename(filepath), str(exc)))
    clean_failures = []
    for filepath in clean_files:
        try:
            output = run_classifier(filepath, 5)
            if output != "CLEAN":
                clean_failures.append((os.path.basename(filepath), output))
        except Exception as exc:
            clean_failures.append((os.path.basename(filepath), str(exc)))
    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed.")
        errors.append("Offending evil files: " + ", ".join(item[0] for item in evil_failures[:10]))
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected.")
        errors.append("Offending clean files: " + ", ".join(item[0] for item in clean_failures[:10]))
    if errors:
        pytest.fail("\n".join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
