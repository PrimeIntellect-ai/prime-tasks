#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import time
import uuid
import pytest

HOME = "/home/user"
PARSER = f"{HOME}/parser"
SOURCE = f"{HOME}/parser.c"
RUNNER = f"{HOME}/test_runner.sh"
STATS = f"{HOME}/stats.log"


def run_checked(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_minimized_crash_txt():
    path = "/home/user/minimized_crash.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert content == "[[[*", f"Expected minimized_crash.txt to contain exactly '[[[*', but got '{content}'"


def test_parser_fixed():
    assert os.path.isfile(PARSER), f"Binary {PARSER} is missing."
    assert os.access(PARSER, os.X_OK), f"Binary {PARSER} is not executable."
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."

    with open(PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The parser must be a compiled executable, not a script or stub."

    # Keep the original regression assertion for the minimized input.
    try:
        result = subprocess.run([PARSER, "[[[*"], timeout=1, capture_output=True, text=True)
        assert result.returncode == 0 or result.returncode != 0, "Parser ran without hanging."
    except subprocess.TimeoutExpired:
        pytest.fail("The parser binary still hangs on the input '[[[*'. The loop termination bug was not correctly fixed.")

    # Exercise the installed binary on a derived, deterministic corpus rather than
    # accepting any executable which merely terminates for one fixed input.
    rng = random.Random(90421)
    cases = ["", "*", "[[[*", "[[[***]]]", "[]", "][", "[[[[*]]]]"]
    cases += ["".join(rng.choice("[]*") for _ in range(rng.randrange(0, 81))) for _ in range(250)]
    for value in cases:
        try:
            result = subprocess.run([PARSER, value], timeout=1, capture_output=True, text=True)
        except subprocess.TimeoutExpired:
            pytest.fail(f"The installed parser hung on generated input {value!r}")
        assert result.returncode == 0, f"The installed parser failed on {value!r}"
        assert result.stdout == "Success\n", f"Unexpected parser output on {value!r}: {result.stdout!r}"

    # Compile the submitted source with a harness exposing parse(), then compare its
    # result against the parser's intended bracket-depth behavior on generated data.
    work = tempfile.mkdtemp(prefix="parser_verify_")
    obj = os.path.join(work, "parser.o")
    harness_c = os.path.join(work, "harness.c")
    harness = os.path.join(work, "harness")
    with open(harness_c, "w") as f:
        f.write(r'''#include <stdio.h>
int parse(const char *str);
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    printf("%d\n", parse(argv[1]));
    return 0;
}
''')
    run_checked(["gcc", "-Dmain=parser_program_main", "-c", SOURCE, "-o", obj], timeout=15)
    run_checked(["gcc", harness_c, obj, "-o", harness], timeout=15)

    for value in cases:
        expected = 1 if value.count("[") - value.count("]") == 0 else 0
        try:
            result = subprocess.run([harness, value], timeout=1, capture_output=True, text=True)
        except subprocess.TimeoutExpired:
            pytest.fail(f"parse() compiled from parser.c hung on generated input {value!r}")
        assert result.returncode == 0, f"parse() harness failed on {value!r}"
        assert result.stdout.strip() == str(expected), (
            f"parse() returned the wrong result for {value!r}: "
            f"expected {expected}, got {result.stdout!r}"
        )


def test_test_runner_script():
    assert os.path.isfile(RUNNER), f"File {RUNNER} is missing."
    assert os.access(RUNNER, os.X_OK), f"File {RUNNER} is not executable."

    token = uuid.uuid4().hex
    backup = f"/tmp/parser_real_{token}"
    call_log = f"/tmp/parser_calls_{token}"
    marker = f"/tmp/parser_marker_{token}"
    pid_file = f"/tmp/parser_pid_{token}"
    proc = None
    os.rename(PARSER, backup)
    try:
        wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {call_log}
if mkdir {marker} 2>/dev/null; then
    echo $$ > {pid_file}
    while :; do :; done
fi
exec {backup} "$@"
'''
        with open(PARSER, "w") as f:
            f.write(wrapper)
        os.chmod(PARSER, 0o755)

        start = time.monotonic()
        proc = subprocess.Popen([RUNNER], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        deadline = time.monotonic() + 5
        while not os.path.exists(pid_file) and time.monotonic() < deadline:
            time.sleep(0.01)
        assert os.path.exists(pid_file), "test_runner.sh did not invoke /home/user/parser."

        with open(pid_file) as f:
            first_pid = int(f.read().strip())
        observed = time.monotonic()
        while os.path.exists(f"/proc/{first_pid}") and time.monotonic() - observed < 5:
            time.sleep(0.01)
        timeout_duration = time.monotonic() - observed
        assert not os.path.exists(f"/proc/{first_pid}"), "The runner did not terminate a hanging parser."
        assert 0.5 <= timeout_duration <= 2.5, (
            f"The per-run timeout was not approximately one second; observed {timeout_duration:.2f}s"
        )

        stdout, stderr = proc.communicate(timeout=60)
        assert proc.returncode == 0, f"test_runner.sh failed. stdout={stdout!r}, stderr={stderr!r}"

        with open(call_log) as f:
            generated = f.read().splitlines()
        assert len(generated) == 1000, f"Expected exactly 1000 parser runs, observed {len(generated)}"
        for index, value in enumerate(generated):
            assert len(value) == 20, f"Generated case {index} has length {len(value)}, not 20"
            assert set(value) <= set("[]*"), f"Generated case {index} contains invalid characters: {value!r}"

        assert os.path.isfile(STATS), "test_runner.sh did not create stats.log"
        with open(STATS) as f:
            content = f.read().strip()
        assert content == "Timeout Failures: 1", (
            "The instrumented run contained exactly one timeout, but stats.log was " + repr(content)
        )
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        if os.path.exists(PARSER):
            os.remove(PARSER)
        if os.path.exists(backup):
            os.rename(backup, PARSER)

    # Execute the submitted fuzzer against the real fixed parser as required.
    result = subprocess.run([RUNNER], timeout=60, capture_output=True, text=True)
    assert result.returncode == 0, (
        f"test_runner.sh failed against the fixed parser: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_stats_log():
    path = "/home/user/stats.log"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the test_runner.sh script?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "Timeout Failures: 0", f"Expected stats.log to contain 'Timeout Failures: 0', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
