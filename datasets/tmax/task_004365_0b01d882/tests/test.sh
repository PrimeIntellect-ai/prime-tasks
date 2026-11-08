#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import random
import string
import subprocess
import time
import urllib.parse
import urllib.request

import pytest

QUERY = "/home/user/query.sh"
SOURCE = "/home/user/workspace/lib/process.c"
LIBRARY = "/home/user/workspace/lib/libprocess.so"
SERVER_SOURCE = "/home/user/workspace/api/server.go"


def expected_text(value, multiplier=7):
    return "".join(chr(ord(c) + multiplier) for c in value[:10])


def api_request(port, value, multiplier=7, timeout=5):
    query = urllib.parse.urlencode({"input": value, "multiplier": str(multiplier)})
    with urllib.request.urlopen(
        f"http://127.0.0.1:{port}/compute?{query}", timeout=timeout
    ) as response:
        assert response.status == 200
        body = json.loads(response.read().decode("utf-8"))
    assert isinstance(body, dict)
    assert set(body) == {"result"}
    return body["result"]


def test_query_script_exists_and_executable():
    assert os.path.exists(QUERY), f"Missing required file: {QUERY}"
    assert os.path.isfile(QUERY), f"Path is not a file: {QUERY}"
    assert os.access(QUERY, os.X_OK), f"File is not executable: {QUERY}"

    content = open(QUERY, encoding="utf-8").read()
    assert "curl" in content, "query.sh must invoke curl"
    assert "127.0.0.1:8080/compute" in content, "query.sh must call the required API"

    no_args = subprocess.run([QUERY], capture_output=True, timeout=5)
    two_args = subprocess.run([QUERY, "one", "two"], capture_output=True, timeout=5)
    assert no_args.returncode != 0, "query.sh must require exactly one argument"
    assert two_args.returncode != 0, "query.sh must reject more than one argument"


def test_c_artifacts_exist_and_are_real_shared_library():
    assert os.path.isfile(SOURCE), f"Missing C source: {SOURCE}"
    assert os.path.isfile(LIBRARY), f"Missing shared library: {LIBRARY}"
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libprocess.so is not an ELF binary"

    header = subprocess.run(
        ["readelf", "-h", LIBRARY], capture_output=True, text=True, timeout=10, check=True
    ).stdout
    assert "DYN (Shared object file)" in header, "libprocess.so is not a shared object"

    symbols = subprocess.run(
        ["nm", "-D", LIBRARY], capture_output=True, text=True, timeout=10, check=True
    ).stdout
    assert "encode_string" in symbols, "libprocess.so does not export encode_string"


def build_c_harness(library, output):
    harness = output + ".c"
    with open(harness, "w", encoding="utf-8") as f:
        f.write(r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
char* encode_string(const char*, int);
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int mult = atoi(argv[1]);
    size_t cap = 1024, len = 0;
    char *input = malloc(cap);
    if (!input) return 3;
    int c;
    while ((c = getchar()) != EOF) {
        if (len + 1 >= cap) {
            cap *= 2;
            char *next = realloc(input, cap);
            if (!next) return 4;
            input = next;
        }
        input[len++] = (char)c;
    }
    input[len] = '\0';
    char *result = encode_string(input, mult);
    if (!result) return 5;
    fwrite(result, 1, strlen(result), stdout);
    free(result);
    free(input);
    return 0;
}
''')
    subprocess.run(
        ["gcc", harness, library, "-Wl,-rpath," + os.path.dirname(library), "-o", output],
        check=True, capture_output=True, timeout=20
    )


def exercise_c_harness(harness):
    cases = [
        (b"A", 7),
        (b"abcdefghij", 7),
        (b"abcdefghijklmnop", 7),
        (b"0123456789" * 10000, 1),
        (b"HELLOWORLD-extra", -2),
    ]
    for data, multiplier in cases:
        result = subprocess.run(
            [harness, str(multiplier)], input=data, capture_output=True, timeout=10
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
        expected = bytes((b + multiplier) % 256 for b in data[:10])
        assert result.stdout == expected


def test_submitted_and_source_built_c_library_are_safe_and_correct(tmp_path):
    submitted_harness = str(tmp_path / "submitted_harness")
    build_c_harness(LIBRARY, submitted_harness)
    exercise_c_harness(submitted_harness)

    rebuilt = str(tmp_path / "libprocess_rebuilt.so")
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-Wall", "-Wextra", "-o", rebuilt, SOURCE],
        check=True, capture_output=True, timeout=20
    )
    rebuilt_harness = str(tmp_path / "rebuilt_harness")
    build_c_harness(rebuilt, rebuilt_harness)
    exercise_c_harness(rebuilt_harness)


def test_required_server_is_available_and_correct():
    for value in ["Hello", "abcdefghijklm", "A B&CD", "012345678901234"]:
        assert api_request(8080, value, 7) == expected_text(value, 7)


def test_go_source_builds_with_cgo_and_rebuilt_server_is_concurrent(tmp_path):
    assert os.path.isfile(SERVER_SOURCE), f"Missing Go source: {SERVER_SOURCE}"
    source = open(SERVER_SOURCE, encoding="utf-8").read()
    assert 'import "C"' in source, "server.go must use CGO"
    assert "encode_string" in source, "server.go must call encode_string"
    assert "globalInput" not in source, "the unsafe shared global C input remains"
    assert ":8080" in source, "server.go must listen on port 8080"

    patched = source.replace(":8080", ":18080")
    assert patched != source
    backup = SERVER_SOURCE + ".verifier-backup"
    binary = str(tmp_path / "server-under-test")
    os.rename(SERVER_SOURCE, backup)
    try:
        with open(SERVER_SOURCE, "w", encoding="utf-8") as f:
            f.write(patched)
        env = os.environ.copy()
        env["CGO_ENABLED"] = "1"
        env["GO111MODULE"] = "off"
        subprocess.run(
            ["go", "build", "-o", binary, "server.go"],
            cwd=os.path.dirname(SERVER_SOURCE), env=env,
            check=True, capture_output=True, timeout=60
        )
    finally:
        if os.path.exists(SERVER_SOURCE):
            os.unlink(SERVER_SOURCE)
        os.rename(backup, SERVER_SOURCE)

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.dirname(LIBRARY) + ":" + env.get("LD_LIBRARY_PATH", "")
    process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 10
        while True:
            if process.poll() is not None:
                out, err = process.communicate()
                pytest.fail(f"rebuilt Go server exited early: {out!r} {err!r}")
            try:
                api_request(18080, "ready", 1, timeout=1)
                break
            except Exception:
                if time.time() >= deadline:
                    pytest.fail("rebuilt Go server did not become available")
                time.sleep(0.1)

        random.seed(9182)
        alphabet = string.ascii_uppercase[:16] + string.digits
        cases = [
            ("".join(random.choices(alphabet, k=random.randint(1, 40))), random.randint(1, 7))
            for _ in range(300)
        ]

        def check(case):
            value, multiplier = case
            return api_request(18080, value, multiplier), expected_text(value, multiplier)

        with concurrent.futures.ThreadPoolExecutor(max_workers=40) as pool:
            for actual, expected in pool.map(check, cases):
                assert actual == expected
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def test_fuzz_equivalence():
    random.seed(42)
    charset = string.ascii_letters + string.digits

    for _ in range(200):
        length = random.randint(1, 20)
        test_input = "".join(random.choices(charset, k=length))
        expected = expected_text(test_input, 7)

        try:
            result = subprocess.run(
                [QUERY, test_input], capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {test_input}")

        assert result.returncode == 0, result.stderr
        actual = result.stdout.strip()
        assert actual == expected, (
            f"Output mismatch on input: '{test_input}'\n"
            f"Expected: '{expected}'\nActual: '{actual}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
