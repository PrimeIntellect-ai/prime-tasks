#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import struct
import subprocess
import tempfile


def test_recovered_dat_exists():
    path = "/home/user/recovered.dat"
    assert os.path.isfile(path), f"Expected file {path} does not exist. You need to recover crash.dat."
    assert os.path.getsize(path) > 0, f"Recovered file {path} is empty."


def test_mre_c_exists():
    path = "/home/user/mre.c"
    assert os.path.isfile(path), f"Expected file {path} does not exist. You need to write the MRE."
    assert os.path.getsize(path) > 0, f"File {path} is empty."


def test_error_log_contents():
    path = "/home/user/error.log"
    assert os.path.isfile(path), f"Expected file {path} does not exist. You need to run your MRE and redirect output."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "Error: 331"
    assert content == expected, f"File {path} content is incorrect. Expected '{expected}', got '{content}'."


def test_recovered_data_is_actual_deleted_payload():
    path = "/home/user/recovered.dat"
    expected = struct.pack("<II16s", 0xDEADBEEF, 331, b"SEGFAULT_CORE_0\0")
    with open(path, "rb") as f:
        actual = f.read()
    assert actual == expected, "recovered.dat is not the deleted crash report payload from diag_fs.img"


def test_mre_compiles_and_parses_payloads():
    source = "/home/user/mre.c"
    recovered = "/home/user/recovered.dat"
    error_log = "/home/user/error.log"

    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "mre")
        build = subprocess.run(
            ["gcc", source, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"mre.c did not compile:\n{build.stderr}"
        assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compiled MRE is not executable"

        with open(recovered, "rb") as f:
            original_recovered = f.read()
        original_log = None
        if os.path.isfile(error_log):
            with open(error_log, "rb") as f:
                original_log = f.read()

        rng = random.SystemRandom()
        codes = [rng.randrange(1, 2**31) for _ in range(3)]
        try:
            for code in codes:
                payload = struct.pack("<II16s", 0xDEADBEEF, code, b"SEGFAULT_CORE_0\0")
                with open(recovered, "wb") as f:
                    f.write(payload)
                if os.path.exists(error_log):
                    os.unlink(error_log)

                run = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert run.returncode == 0, f"Compiled MRE exited with status {run.returncode}: {run.stderr}"

                outputs = []
                if run.stdout.strip():
                    outputs.append(run.stdout.strip())
                if os.path.isfile(error_log):
                    with open(error_log, "r") as f:
                        outputs.append(f.read().strip())

                expected = f"Error: {code}"
                assert expected in outputs, (
                    f"Compiled MRE did not parse a valid payload correctly. "
                    f"Expected '{expected}', observed {outputs!r}."
                )
        finally:
            with open(recovered, "wb") as f:
                f.write(original_recovered)
            if original_log is None:
                if os.path.exists(error_log):
                    os.unlink(error_log)
            else:
                with open(error_log, "wb") as f:
                    f.write(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
