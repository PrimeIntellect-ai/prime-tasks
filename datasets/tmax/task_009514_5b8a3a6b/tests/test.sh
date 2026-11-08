#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import shutil
import string
import subprocess
import tempfile
import urllib.parse

LIB = "/home/user/libdecoder.so"
SOURCE = "/home/user/decoder.c"
SCRIPT = "/home/user/run.py"
URLS = "/home/user/urls.txt"
RESULTS = "/home/user/results.txt"

CANONICAL_URLS = """/api/v1/process?action=start&payload=Hello%20World
/api/v1/log?payload=This%20is%20a%20very%20long%20string%20that%20will%20overflow%20the%20thirty%20two%20byte%20buffer
/api/v2/update?id=99&payload=Secret%2BData%2521
"""
CANONICAL_RESULTS = [
    "Hello World",
    "This is a very long string that will overflow the thirty two byte buffer",
    "Secret Data!",
]


def c_decode_expected(value):
    out = []
    i = 0
    while i < len(value):
        if value[i] == "%" and i + 2 < len(value):
            out.append(chr(int(value[i + 1:i + 3], 16)))
            i += 3
        elif value[i] == "+":
            out.append(" ")
            i += 1
        else:
            out.append(value[i])
            i += 1
    return "".join(out)


def run_script(url_text):
    with open(URLS, "w", encoding="utf-8") as f:
        f.write(url_text)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert completed.returncode == 0, (
        f"run.py failed with exit code {completed.returncode}:\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "run.py did not create /home/user/results.txt"
    with open(RESULTS, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def test_libdecoder_so_exists():
    assert os.path.isfile(LIB), f"Shared library not found: {LIB}. Did you compile the C code?"


def test_decoder_c_fixed():
    assert os.path.isfile(SOURCE), f"Source file not found: {SOURCE}"
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()
    assert "char buffer[32];" not in content, (
        "The C code still contains the buggy fixed-size buffer 'char buffer[32];'."
    )


def test_library_behavior_and_memory_safety():
    lib = ctypes.CDLL(LIB)
    assert hasattr(lib, "decode_url_payload"), "Shared library does not export decode_url_payload"
    decode = lib.decode_url_payload
    decode.argtypes = [ctypes.c_char_p]
    decode.restype = ctypes.c_char_p

    cases = {
        b"Hello%20World": b"Hello World",
        b"plus+becomes+spaces": b"plus becomes spaces",
        b"Secret+Data%21": b"Secret Data!",
        b"%41%42%43-%7a": b"ABC-z",
        b"plain-text_123": b"plain-text_123",
    }
    for encoded, expected in cases.items():
        assert decode(encoded) == expected

    # This is far beyond the old 32-byte local buffer and catches the overflow.
    long_encoded = (b"segment%20with+spaces-" * 25000) + b"END%21"
    long_expected = (b"segment with spaces-" * 25000) + b"END!"
    assert decode(long_encoded) == long_expected

    for _ in range(30):
        token = "".join(random.choice(string.ascii_letters + string.digits) for _ in range(80))
        encoded = (token + "%2Fpart+tail%21").encode("ascii")
        expected = (token + "/part tail!").encode("ascii")
        assert decode(encoded) == expected


def test_run_py_executes_and_uses_library():
    assert os.path.isfile(SCRIPT), f"Python script not found: {SCRIPT}"
    with open(SCRIPT, "r", encoding="utf-8") as f:
        script_content = f.read()
    assert "ctypes" in script_content, "run.py does not use ctypes"
    assert "decode_url_payload" in script_content, "run.py does not reference decode_url_payload"
    assert "c_char_p" in script_content, "run.py does not set/use ctypes.c_char_p"

    with tempfile.TemporaryDirectory() as td:
        saved_urls = os.path.join(td, "urls.txt")
        saved_lib = os.path.join(td, "libdecoder.so")
        if os.path.exists(URLS):
            shutil.copy2(URLS, saved_urls)
        shutil.copy2(LIB, saved_lib)

        try:
            # Retain the original exact output assertion, but obtain the output by
            # actually running the submitted script.
            actual_lines = run_script(CANONICAL_URLS)
            filtered = [line.strip() for line in actual_lines if line.strip()]
            assert len(filtered) == len(CANONICAL_RESULTS), (
                f"Expected {len(CANONICAL_RESULTS)} lines in results.txt, but got {len(filtered)}."
            )
            for i, (actual, expected) in enumerate(zip(filtered, CANONICAL_RESULTS)):
                assert actual == expected, (
                    f"Line {i + 1} mismatch. Expected '{expected}', got '{actual}'."
                )

            # Exercise URL parsing and decoding on unpredictable additional inputs.
            nonce = "".join(random.choice(string.ascii_letters + string.digits) for _ in range(24))
            intermediate_values = [
                nonce + "%20alpha+beta%21",
                "%5B" + nonce[::-1] + "%5D+tail",
                "prefix%2F" + nonce + "%3Fvalue%3D42",
                nonce.lower() + "%2Bencoded+plus",
            ]
            routes = []
            expected = []
            for i, intermediate in enumerate(intermediate_values):
                query_value = urllib.parse.quote_plus(intermediate, safe="")
                routes.append(f"/random/{i}?ignored={i}&payload={query_value}&other=x")
                parsed_value = urllib.parse.parse_qs(
                    urllib.parse.urlsplit(routes[-1]).query
                )["payload"][0]
                expected.append(c_decode_expected(parsed_value))
            assert run_script("\n".join(routes) + "\n") == expected

            # Replace the library temporarily with a randomized probe. If run.py
            # computes results itself or ignores the FFI return value, this fails.
            marker = "ffi_" + "".join(random.choice(string.ascii_letters) for _ in range(28))
            probe_c = os.path.join(td, "probe.c")
            probe_so = os.path.join(td, "probe.so")
            with open(probe_c, "w", encoding="utf-8") as f:
                f.write(
                    '#include <stddef.h>\n'
                    f'char* decode_url_payload(const char* src) {{ (void)src; return "{marker}"; }}\n'
                )
            subprocess.run(
                ["gcc", "-shared", "-fPIC", "-o", probe_so, probe_c],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
            )
            shutil.copy2(probe_so, LIB)
            probe_urls = (
                "/probe/one?payload=unpredictable%2520input\n"
                "/probe/two?x=1&payload=another%2Bvalue\n"
            )
            assert run_script(probe_urls) == [marker, marker], (
                "run.py did not use the return value from decode_url_payload in libdecoder.so"
            )
        finally:
            shutil.copy2(saved_lib, LIB)
            if os.path.exists(saved_urls):
                shutil.copy2(saved_urls, URLS)
            else:
                with open(URLS, "w", encoding="utf-8") as f:
                    f.write(CANONICAL_URLS)

        # Leave results.txt in the required canonical final state and recheck it.
        final_lines = run_script(CANONICAL_URLS)
        assert final_lines == CANONICAL_RESULTS
        if os.path.exists(saved_urls):
            shutil.copy2(saved_urls, URLS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
