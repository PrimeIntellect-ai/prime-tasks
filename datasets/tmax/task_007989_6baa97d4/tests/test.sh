#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import textwrap
import pytest

SCRIPT_PATH = "/home/user/ci_benchmark.sh"
PROJECT_DIR = "/home/user/rust_parser"
ARTIFACT_PATH = "/home/user/artifacts/bench_results.json"
BINARY_PATH = "/home/user/rust_parser/target/release/rust_parser"
INPUT_PATH = "/home/user/rust_parser/input.log"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_artifact():
    time_path = "/usr/bin/time"
    time_real = "/usr/bin/time.verifier-real"
    cargo_path = "/usr/bin/cargo"
    cargo_real = "/usr/bin/cargo.verifier-real"
    time_log = "/tmp/verifier-time.log"
    time_ran = "/tmp/verifier-time-ran.log"
    cargo_log = "/tmp/verifier-cargo.log"

    user_time_text = f"{random.randint(10, 90)}.{random.randint(10, 99)}"
    expected_user_time = float(user_time_text)
    expected_rss = random.randint(41000, 99000)

    for path in (time_log, time_ran, cargo_log):
        if os.path.exists(path):
            os.remove(path)
    if os.path.exists(ARTIFACT_PATH):
        os.remove(ARTIFACT_PATH)
    if os.path.exists(BINARY_PATH):
        os.remove(BINARY_PATH)

    assert os.path.exists(time_path), "/usr/bin/time is missing"
    assert os.path.exists(cargo_path), "/usr/bin/cargo is missing"
    assert not os.path.lexists(time_real), f"Unexpected pre-existing path: {time_real}"
    assert not os.path.lexists(cargo_real), f"Unexpected pre-existing path: {cargo_real}"

    os.rename(time_path, time_real)
    os.rename(cargo_path, cargo_real)
    try:
        with open(cargo_path, "w") as f:
            f.write(textwrap.dedent(f"""\
                #!/bin/bash
                {{
                    printf 'PWD=%s\\n' "$PWD"
                    printf 'ARG=%s\\n' "$@"
                }} > {cargo_log}
                exec {cargo_real} "$@"
            """))
        os.chmod(cargo_path, 0o755)

        with open(time_path, "w") as f:
            f.write(textwrap.dedent(f"""\
                #!/bin/bash
                {{
                    printf 'PWD=%s\\n' "$PWD"
                    printf 'ARG=%s\\n' "$@"
                }} > {time_log}

                if [ "$1" != "-v" ]; then
                    echo "verifier time wrapper requires -v" >&2
                    exit 97
                fi
                shift
                "$@"
                status=$?
                printf 'STATUS=%s\\n' "$status" > {time_ran}
                echo 'User time (seconds): {user_time_text}' >&2
                echo 'Maximum resident set size (kbytes): {expected_rss}' >&2
                exit "$status"
            """))
        os.chmod(time_path, 0o755)

        result = subprocess.run(
            [SCRIPT_PATH], capture_output=True, text=True, timeout=180
        )
    finally:
        if os.path.lexists(time_path):
            os.remove(time_path)
        if os.path.lexists(time_real):
            os.rename(time_real, time_path)
        if os.path.lexists(cargo_path):
            os.remove(cargo_path)
        if os.path.lexists(cargo_real):
            os.rename(cargo_real, cargo_path)

    assert result.returncode == 0, (
        f"Script failed to execute. stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    assert os.path.isfile(cargo_log), "The script did not invoke cargo."
    with open(cargo_log) as f:
        cargo_lines = f.read().splitlines()
    assert f"PWD={PROJECT_DIR}" in cargo_lines, "cargo was not run from the Rust project directory."
    cargo_args = [line[4:] for line in cargo_lines if line.startswith("ARG=")]
    assert "build" in cargo_args, "The script did not run cargo build."
    assert "--release" in cargo_args, "The Rust project was not built in release mode."
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), (
        "The release binary was not rebuilt."
    )

    assert os.path.isfile(time_log), "The script did not invoke /usr/bin/time."
    with open(time_log) as f:
        time_lines = f.read().splitlines()
    assert f"PWD={PROJECT_DIR}" in time_lines, "/usr/bin/time was not run from the project directory."
    time_args = [line[4:] for line in time_lines if line.startswith("ARG=")]
    assert time_args and time_args[0] == "-v", "The script did not invoke /usr/bin/time -v."
    assert len(time_args) == 3, "time must run the parser with exactly the input file argument."

    invoked_binary = time_args[1]
    if not os.path.isabs(invoked_binary):
        invoked_binary = os.path.normpath(os.path.join(PROJECT_DIR, invoked_binary))
    invoked_input = time_args[2]
    if not os.path.isabs(invoked_input):
        invoked_input = os.path.normpath(os.path.join(PROJECT_DIR, invoked_input))
    assert invoked_binary == BINARY_PATH, "time did not run target/release/rust_parser."
    assert invoked_input == INPUT_PATH, "The parser was not run on input.log."
    assert os.path.isfile(time_ran), "The timed parser command was not executed."
    with open(time_ran) as f:
        assert f.read().strip() == "STATUS=0", "The timed parser command did not complete successfully."

    assert os.path.isfile(ARTIFACT_PATH), f"Artifact {ARTIFACT_PATH} was not created by the script."
    with open(ARTIFACT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Artifact {ARTIFACT_PATH} does not contain valid JSON.")

    assert "user_time_seconds" in data, "JSON missing key: 'user_time_seconds'"
    assert "max_rss_kb" in data, "JSON missing key: 'max_rss_kb'"
    assert isinstance(data["user_time_seconds"], (int, float)), "'user_time_seconds' must be a number (float or int)."
    assert isinstance(data["max_rss_kb"], int), "'max_rss_kb' must be an integer."
    assert set(data) == {"user_time_seconds", "max_rss_kb"}, "JSON must contain exactly the two required keys."
    assert data["user_time_seconds"] == expected_user_time, (
        "user_time_seconds was not parsed from /usr/bin/time -v stderr."
    )
    assert data["max_rss_kb"] == expected_rss, (
        "max_rss_kb was not parsed from /usr/bin/time -v stderr."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
