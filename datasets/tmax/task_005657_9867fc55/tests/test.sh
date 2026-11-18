#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile

PROJECT_DIR = "/home/user/project"
CRASH_INFO = os.path.join(PROJECT_DIR, "crash_info.txt")
BUILD_STATUS = os.path.join(PROJECT_DIR, "build_status.txt")
BUILD_SH = os.path.join(PROJECT_DIR, "build.sh")
OUTPUT_LOG = os.path.join(PROJECT_DIR, "output.log")
PROCESSOR_SOURCE = os.path.join(PROJECT_DIR, "processor.c")


def test_crash_info_correct():
    assert os.path.exists(CRASH_INFO), f"{CRASH_INFO} is missing. You must create it."
    with open(CRASH_INFO, "r") as f:
        content = f.read().strip()
    assert content == "4", f"Expected {CRASH_INFO} to contain '4', but found '{content}'."


def test_build_status_correct():
    assert os.path.exists(BUILD_STATUS), f"{BUILD_STATUS} is missing. Did you run build.sh?"
    with open(BUILD_STATUS, "r") as f:
        content = f.read().strip()
    assert "Build Success" in content, f"Expected {BUILD_STATUS} to contain 'Build Success'."


def test_processor_fixes_and_build_succeeds():
    assert os.path.exists(BUILD_SH), f"{BUILD_SH} is missing."
    assert os.access(BUILD_SH, os.X_OK), f"{BUILD_SH} is not executable."

    result = subprocess.run(
        [BUILD_SH],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"build.sh failed with exit code {result.returncode}."

    assert os.path.exists(OUTPUT_LOG), f"{OUTPUT_LOG} was not generated."
    with open(OUTPUT_LOG, "r") as f:
        log_content = f.read()
    assert "Record 0" in log_content, "Record 0 was not processed."
    assert "Record 4" in log_content, "Record 4 (the oversized record) was not processed. It must be handled without crashing."
    assert "Record 5" in log_content, "Record 5 was not processed. Ensure the file pointer is correctly advanced after an oversized record."

    with open(BUILD_STATUS, "r") as f:
        status = f.read().strip()
    assert "Build Success" in status, "build.sh did not generate a successful build_status.txt."

    # Compile the submitted C source ourselves so replacing build.sh with a
    # script that merely prints expected keywords cannot pass verification.
    assert os.path.isfile(PROCESSOR_SOURCE), f"{PROCESSOR_SOURCE} is missing or is not a regular file."
    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "processor_under_test")
        compile_result = subprocess.run(
            [
                "/usr/bin/gcc", "-std=c11", "-g", "-O0",
                "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                PROCESSOR_SOURCE, "-o", executable,
            ],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            "processor.c did not compile independently:\n"
            + compile_result.stdout + compile_result.stderr
        )

        alphabet = string.ascii_letters + string.digits
        def payload(length):
            return ''.join(secrets.choice(alphabet) for _ in range(length)).encode("ascii")

        # Values are generated only at verification time. There are multiple
        # oversized records, each followed by another record, to verify both
        # bounds safety and correct advancement of the input stream.
        records = [
            (secrets.randbelow(250) + 1, payload(9)),
            (secrets.randbelow(250) + 1, payload(60)),
            (secrets.randbelow(250) + 1, payload(13)),
            (secrets.randbelow(250) + 1, payload(31)),
            (secrets.randbelow(250) + 1, payload(90)),
            (secrets.randbelow(250) + 1, payload(17)),
            (secrets.randbelow(250) + 1, payload(5)),
        ]
        data_path = os.path.join(td, "verification_data.bin")
        with open(data_path, "wb") as f:
            for record_type, data in records:
                f.write(bytes((record_type, len(data))))
                f.write(data)

        run_env = os.environ.copy()
        run_env["ASAN_OPTIONS"] = "detect_leaks=0:abort_on_error=1"
        run_env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
        run_result = subprocess.run(
            [executable, data_path],
            cwd=td,
            capture_output=True,
            text=True,
            env=run_env,
            timeout=20,
        )
        assert run_result.returncode == 0, (
            "The independently compiled processor crashed or reported a sanitizer error:\n"
            + run_result.stdout + run_result.stderr
        )

        lines = run_result.stdout.splitlines()
        assert len(lines) == len(records), (
            f"Expected exactly {len(records)} processed records, got {len(lines)}. "
            f"Output was: {run_result.stdout!r}"
        )
        pattern = re.compile(r"^Record (\d+) - Type: (\d+), Data: (.*)$")
        for index, (line, (expected_type, expected_bytes)) in enumerate(zip(lines, records)):
            match = pattern.fullmatch(line)
            assert match, f"Malformed output for record {index}: {line!r}"
            assert int(match.group(1)) == index, f"Wrong record index in line: {line!r}"
            assert int(match.group(2)) == expected_type, f"Wrong type for record {index}."

            shown = match.group(3).encode("ascii")
            if len(expected_bytes) <= 31:
                assert shown == expected_bytes, f"Incorrect data for record {index}."
            else:
                # Keeping the complete value or truncating it to the original
                # 32-byte buffer's 31-byte capacity are both permitted.
                assert shown == expected_bytes or shown == expected_bytes[:31], (
                    f"Oversized record {index} was not handled as a complete value "
                    "or a valid 31-byte truncation."
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
