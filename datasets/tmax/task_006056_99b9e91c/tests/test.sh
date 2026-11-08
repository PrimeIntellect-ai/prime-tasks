#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import heapq
import json
import os
import stat
import subprocess

BASE_DIR = "/home/user/ci_cd_test"
APP_PATH = os.path.join(BASE_DIR, "pqueue_app")
SCRIPT_PATH = os.path.join(BASE_DIR, "run_tests.sh")
REPORT_PATH = os.path.join(BASE_DIR, "test_report.txt")


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        **kwargs,
    )


def expected_pqueue_output(commands):
    heap = []
    popped = []
    for command in commands:
        if command.startswith("push "):
            heapq.heappush(heap, -int(command.split()[1]))
        elif command == "pop":
            popped.append(str(-heapq.heappop(heap)) if heap else "-1")
        else:
            raise AssertionError(f"Unknown test command: {command}")
    return ((" ".join(popped) + " ") if popped else "") + "\n"


def test_make_builds_and_application_behaves_correctly():
    # Remove prior products so success requires the submitted Makefile to build the target.
    for name in ("pqueue_app", "main.o", "pqueue.o"):
        path = os.path.join(BASE_DIR, name)
        if os.path.lexists(path):
            os.remove(path)

    result = run(["make"])
    assert result.returncode == 0, f"make failed:\n{result.stdout}{result.stderr}"

    assert os.path.isfile(APP_PATH), (
        f"Executable {APP_PATH} does not exist. The Makefile was likely not fixed or 'make' was not run."
    )
    assert os.access(APP_PATH, os.X_OK), f"File {APP_PATH} is not executable."
    with open(APP_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pqueue_app is not a compiled ELF executable."

    cases = [
        ["pop", "pop"],
        ["push -7", "push 42", "push 3", "pop", "pop", "pop", "pop"],
        ["push 11", "push 11", "push 100", "push 2", "pop", "pop", "pop"],
    ]
    for commands in cases:
        result = run([APP_PATH, *commands])
        assert result.returncode == 0, f"pqueue_app failed for {commands}: {result.stderr}"
        expected = expected_pqueue_output(commands)
        assert result.stdout == expected, (
            f"pqueue_app returned {result.stdout!r} for {commands}; expected {expected!r}"
        )


def test_bash_script_fixed_report_matches_and_runner_invokes_app():
    assert os.path.isfile(SCRIPT_PATH), f"Bash script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "declare -A test_cases" in content, (
        "run_tests.sh does not contain 'declare -A test_cases'. The associative array declaration was not fixed."
    )
    assert "declare -a test_cases" not in content, (
        "run_tests.sh still contains the broken 'declare -a test_cases'."
    )

    assert os.path.isfile(REPORT_PATH), (
        f"Test report {REPORT_PATH} does not exist. Did you redirect the output of run_tests.sh?"
    )
    with open(REPORT_PATH, "r") as f:
        report = f.read()

    expected_lines = [
        "Test 'push 5 push 10 pop' - PASS",
        "Test 'push 1 pop pop' - PASS",
        "Test 'push 20 push 5 push 30 pop pop' - PASS",
    ]
    for line in expected_lines:
        assert line in report, (
            f"Expected line '{line}' not found in {REPORT_PATH}. The tests might have failed or the report is incomplete."
        )

    result = run(["bash", "./run_tests.sh"])
    assert result.returncode == 0, f"run_tests.sh failed:\n{result.stdout}{result.stderr}"
    assert "FAIL" not in result.stdout, f"run_tests.sh reported a failure:\n{result.stdout}"
    assert result.stdout == report, (
        "test_report.txt is not the exact current standard output of run_tests.sh"
    )

    # Replace the known-good application temporarily with an instrumented emulator.
    # This verifies that the runner really invokes pqueue_app for each declared case,
    # rather than merely printing prewritten PASS messages.
    real_app = APP_PATH + ".verifier-real"
    log_path = "/tmp/pqueue_runner_calls.jsonl"
    if os.path.exists(log_path):
        os.remove(log_path)
    os.rename(APP_PATH, real_app)
    wrapper = '''#!/usr/bin/env python3
import heapq, json, os, shlex, sys
words = []
for arg in sys.argv[1:]:
    words.extend(shlex.split(arg))
ops = []
i = 0
while i < len(words):
    if words[i] == "push" and i + 1 < len(words):
        ops.append("push " + words[i + 1])
        i += 2
    elif words[i] == "pop":
        ops.append("pop")
        i += 1
    else:
        i += 1
with open(os.environ["PQUEUE_CALL_LOG"], "a") as f:
    f.write(json.dumps(ops) + "\\n")
heap = []
out = []
for op in ops:
    if op.startswith("push "):
        heapq.heappush(heap, -int(op.split()[1]))
    else:
        out.append(str(-heapq.heappop(heap)) if heap else "-1")
sys.stdout.write(((" ".join(out) + " ") if out else "") + "\\n")
'''
    try:
        with open(APP_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(APP_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                           stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        env = os.environ.copy()
        env["PQUEUE_CALL_LOG"] = log_path
        instrumented = run(["bash", "./run_tests.sh"], env=env)
        assert instrumented.returncode == 0, (
            f"run_tests.sh failed with an instrumented pqueue_app:\n"
            f"{instrumented.stdout}{instrumented.stderr}"
        )
        assert "FAIL" not in instrumented.stdout, instrumented.stdout
        assert os.path.isfile(log_path), "run_tests.sh never invoked ./pqueue_app"
        with open(log_path) as f:
            calls = [tuple(json.loads(line)) for line in f if line.strip()]
        required_calls = collections.Counter({
            ("push 5", "push 10", "pop"): 1,
            ("push 1", "pop", "pop"): 1,
            ("push 20", "push 5", "push 30", "pop", "pop"): 1,
        })
        observed = collections.Counter(calls)
        for call, count in required_calls.items():
            assert observed[call] >= count, (
                f"run_tests.sh did not invoke pqueue_app for test case {call}; observed calls: {calls}"
            )
    finally:
        if os.path.lexists(APP_PATH):
            os.remove(APP_PATH)
        os.rename(real_app, APP_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
