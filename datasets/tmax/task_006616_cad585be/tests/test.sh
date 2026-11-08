#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib
import json
import os
import secrets
import shutil
import sqlite3
import string
import subprocess
import sys
import tempfile

import pytest

APP = "/home/user/app"
DB = f"{APP}/test.db"
REPORT = f"{APP}/qa_report.json"
QA_TEST = f"{APP}/qa_test.py"
C_SOURCE = f"{APP}/libecc/ecc.c"
LIBRARY = f"{APP}/libecc/libecc.so"


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, text=True, capture_output=True, **kwargs)


def reset_and_setup_database():
    for path in (DB, REPORT):
        if os.path.exists(path):
            os.remove(path)
    run_checked([sys.executable, f"{APP}/setup_db.py"], cwd=APP)


def run_qa_test():
    assert os.path.isfile(QA_TEST), f"QA test script not found at {QA_TEST}"
    run_checked([sys.executable, QA_TEST], cwd=APP)


@pytest.fixture(scope="session", autouse=True)
def prepare_and_execute_submission():
    assert os.path.isfile(LIBRARY), f"Shared library not found at {LIBRARY}. Did you compile it?"

    # Import both refactored models in a clean interpreter and verify that their
    # original relationship methods still resolve to the opposite class.
    model_check = r'''
from models.file_meta import FileMeta
from models.checksum_data import ChecksumData
assert FileMeta.name == "FileMeta"
assert ChecksumData.name == "ChecksumData"
assert FileMeta().get_related() is ChecksumData
assert ChecksumData().get_related() is FileMeta
'''
    run_checked([sys.executable, "-c", model_check], cwd=APP)

    original_library = open(LIBRARY, "rb").read()
    nonce = "QA_" + "".join(secrets.choice(string.ascii_uppercase) for _ in range(24))
    expected_probe_result = ("A" * 100) + nonce

    # Temporarily substitute an ABI-compatible probe. A conforming qa_test.py
    # records the value actually returned by calculate_checksum; a hardcoded
    # report cannot know the per-run nonce.
    with tempfile.TemporaryDirectory() as td:
        probe_c = os.path.join(td, "probe.c")
        probe_so = os.path.join(td, "libecc.so")
        expected_input = "A" * 100
        with open(probe_c, "w") as f:
            f.write(f'''#include <stdio.h>\n#include <string.h>\nstatic char output[512];\nchar* calculate_checksum(const char* input) {{\n    if (!input || strcmp(input, "{expected_input}") != 0) return "WRONG_INPUT";\n    snprintf(output, sizeof(output), "%s%s", input, "{nonce}");\n    return output;\n}}\n''')
        run_checked(["gcc", "-shared", "-fPIC", "-o", probe_so, probe_c])
        try:
            shutil.copyfile(probe_so, LIBRARY)
            reset_and_setup_database()
            run_qa_test()
            with open(REPORT) as f:
                probe_report = json.load(f)
            assert probe_report.get("payload_checksum") == expected_probe_result, (
                "qa_test.py did not save the value returned by calculate_checksum "
                "for exactly 100 uppercase 'A' characters"
            )

            conn = sqlite3.connect(DB)
            try:
                assert conn.execute(
                    "SELECT 1 FROM file_meta WHERE id = 1 AND name = 'test_payload'"
                ).fetchone() is not None
                assert conn.execute(
                    "SELECT 1 FROM checksum_data WHERE file_id = 1 AND checksum = 'dummy'"
                ).fetchone() is not None
            finally:
                conn.close()
        finally:
            with open(LIBRARY, "wb") as f:
                f.write(original_library)

    # Produce and retain the required final state using the submitted library.
    reset_and_setup_database()
    run_qa_test()
    yield


def test_database_created_and_populated():
    assert os.path.isfile(DB), f"Database file not found at {DB}"

    conn = sqlite3.connect(DB)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='file_meta'")
        assert cursor.fetchone() is not None, "Table 'file_meta' does not exist in the database."

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='checksum_data'")
        assert cursor.fetchone() is not None, "Table 'checksum_data' does not exist in the database."

        cursor.execute("SELECT count(*) FROM file_meta")
        assert cursor.fetchone()[0] >= 1, "Expected at least 1 row in 'file_meta' table."

        cursor.execute("SELECT count(*) FROM checksum_data")
        assert cursor.fetchone()[0] >= 1, "Expected at least 1 row in 'checksum_data' table."

        assert cursor.execute(
            "SELECT 1 FROM file_meta WHERE id = 1 AND name = 'test_payload'"
        ).fetchone() is not None, "qa_test.py did not insert the required file_meta row."
        assert cursor.execute(
            "SELECT 1 FROM checksum_data WHERE file_id = 1 AND checksum = 'dummy'"
        ).fetchone() is not None, "qa_test.py did not insert the required checksum_data row."
    finally:
        conn.close()


def test_shared_library_compiled_and_callable():
    assert os.path.isfile(LIBRARY), f"Shared library not found at {LIBRARY}. Did you compile it?"
    library = ctypes.CDLL(LIBRARY)
    function = library.calculate_checksum
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_char_p

    payloads = [
        b"",
        b"Z",
        "".join(secrets.choice(string.ascii_uppercase) for _ in range(137)).encode(),
        "".join(secrets.choice(string.ascii_uppercase) for _ in range(8192)).encode(),
        b"Q" * (1024 * 1024),
    ]
    for payload in payloads:
        result = function(payload)
        assert result is not None
        assert result == payload + b"1234", "calculate_checksum returned an incorrect value"


def test_qa_report_json():
    assert os.path.isfile(REPORT), f"QA report not found at {REPORT}"
    with open(REPORT) as f:
        data = json.load(f)

    assert set(data) == {"db_created", "payload_checksum"}, "QA report has an incorrect format."
    assert data["db_created"] is True, "Expected 'db_created' to be true."
    expected_checksum = ("A" * 100) + "1234"
    assert data["payload_checksum"] == expected_checksum, (
        "Expected payload_checksum to be 100 'A's followed by '1234', "
        f"but got '{data['payload_checksum']}'"
    )


def test_c_extension_fixed():
    assert os.path.isfile(C_SOURCE), f"C file not found at {C_SOURCE}"
    with open(C_SOURCE) as f:
        content = f.read()

    # Preserve the original source assertion.
    assert "malloc(len + 1)" not in content, (
        "The memory allocation bug in ecc.c has not been fixed "
        "(still using malloc(len + 1))."
    )

    # Recompile the submitted source with AddressSanitizer and exercise both
    # correctness and heap safety independently of the submitted .so file.
    harness = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
char* calculate_checksum(const char* input);
int main(void) {
    const size_t sizes[] = {0, 1, 100, 8192, 2097152};
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        size_t n = sizes[i];
        char *input = malloc(n + 1);
        if (!input) return 10;
        memset(input, 'K' + (int)i, n);
        input[n] = '\0';
        char *output = calculate_checksum(input);
        if (!output) return 11;
        if (strlen(output) != n + 4) return 12;
        if (memcmp(output, input, n) != 0) return 13;
        if (memcmp(output + n, "1234", 5) != 0) return 14;
        free(output);
        free(input);
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "harness.c")
        executable = os.path.join(td, "asan_check")
        with open(harness_path, "w") as f:
            f.write(harness)
        run_checked([
            "gcc", "-fsanitize=address", "-fno-omit-frame-pointer", "-O1",
            "-o", executable, C_SOURCE, harness_path,
        ])
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        run_checked([executable], env=env)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
