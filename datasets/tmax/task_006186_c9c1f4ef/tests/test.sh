#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile


def test_solution_txt_exists_and_correct():
    path = "/home/user/solution.txt"
    assert os.path.exists(path), f"File {path} is missing. Did you redirect the output?"
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "VULNERABILITY_CONFIRMED: SQL_INJECTION_BYPASS"
    assert expected in content, f"Expected '{expected}' in {path}, but got '{content}'"


def test_trigger_cpp_exists():
    path = "/home/user/trigger.cpp"
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, "r") as f:
        content = f.read()

    assert "ANALYZE_DBG_" in content, f"Expected environment variable prefix 'ANALYZE_DBG_' in {path}"


def test_trigger_binary_exists():
    path = "/home/user/trigger"
    assert os.path.exists(path), f"File {path} is missing. Did you compile trigger.cpp?"
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def reconstruct_inputs():
    fatal_pid = None
    processed = {}
    line_re = re.compile(r"\[PID (\d+)\]")
    input_re = re.compile(r"Processed input: (.*)$")

    with open("/home/user/service.log", "r") as f:
        for line in f:
            pid_match = line_re.search(line)
            if not pid_match:
                continue
            pid = pid_match.group(1)
            input_match = input_re.search(line.rstrip("\n"))
            if input_match:
                processed.setdefault(pid, []).append(input_match.group(1))
            if "FATAL: SEGFAULT" in line:
                fatal_pid = pid
                break

    assert fatal_pid is not None, "No PID with FATAL: SEGFAULT was found"
    assert len(processed.get(fatal_pid, [])) >= 3, "Fatal PID did not process three inputs"
    return processed[fatal_pid][-3:]


def discover_hidden_env(binary):
    output = subprocess.check_output(["strings", "-a", binary], text=True)
    matches = re.findall(r"ANALYZE_DBG_[A-Za-z0-9_]+", output)
    assert matches, "No ANALYZE_DBG_ environment variable was found in analyzer"
    return matches[0]


def clean_environment(hidden_env):
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("ANALYZE_DBG_"):
            env.pop(key, None)
    env.pop(hidden_env, None)
    return env


def read_trace(path):
    if not os.path.exists(path):
        return []
    with open(path, "r") as f:
        return [json.loads(line) for line in f if line.strip()]


def run_and_check(program, expected_args, hidden_env, expected_output, trace_path):
    if os.path.exists(trace_path):
        os.unlink(trace_path)

    env = clean_environment(hidden_env)
    proc = subprocess.run(
        [program],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        cwd="/home/user",
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"{program} exited with {proc.returncode}; stderr was: {proc.stderr!r}"
    )
    assert proc.stdout.strip() == expected_output, (
        f"{program} output {proc.stdout!r}, expected analyzer output {expected_output!r}"
    )

    calls = read_trace(trace_path)
    assert calls, f"{program} did not execute /home/user/analyzer"
    assert any(
        call.get("args") == expected_args and call.get("hidden_value") == "1"
        for call in calls
    ), (
        f"{program} did not invoke analyzer with the reconstructed arguments "
        f"and {hidden_env}=1; observed calls: {calls!r}"
    )


def test_trigger_executes_analyzer_correctly():
    analyzer = "/home/user/analyzer"
    expected_args = reconstruct_inputs()
    hidden_env = discover_hidden_env(analyzer)

    backup_fd, backup = tempfile.mkstemp(prefix="verifier_analyzer_", dir="/tmp")
    os.close(backup_fd)
    trace_fd, trace_path = tempfile.mkstemp(prefix="verifier_trace_", dir="/tmp")
    os.close(trace_fd)
    os.unlink(trace_path)
    compiled_fd, compiled_trigger = tempfile.mkstemp(prefix="verifier_trigger_", dir="/tmp")
    os.close(compiled_fd)
    os.unlink(compiled_trigger)

    shutil.copy2(analyzer, backup)
    try:
        reference_env = clean_environment(hidden_env)
        reference_env[hidden_env] = "1"
        reference = subprocess.run(
            [backup] + expected_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=reference_env,
            timeout=10,
        )
        assert reference.returncode == 0, "Analyzer rejected the reconstructed invocation"
        expected_output = reference.stdout.strip()
        assert expected_output, "Correct analyzer invocation produced no output"

        wrapper = f'''#!/usr/bin/python3
import json
import os
import sys
with open({trace_path!r}, "a") as f:
    f.write(json.dumps({{"args": sys.argv[1:], "hidden_value": os.environ.get({hidden_env!r})}}) + "\\n")
os.execv({backup!r}, [{backup!r}] + sys.argv[1:])
'''
        with open(analyzer, "w") as f:
            f.write(wrapper)
        os.chmod(analyzer, 0o755)

        run_and_check(
            "/home/user/trigger", expected_args, hidden_env, expected_output, trace_path
        )

        with open("/home/user/solution.txt", "r") as f:
            solution = f.read().strip()
        assert solution == expected_output, (
            "solution.txt does not match the output produced by the required analyzer invocation"
        )

        compile_proc = subprocess.run(
            ["g++", "/home/user/trigger.cpp", "-o", compiled_trigger],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_proc.returncode == 0, (
            f"trigger.cpp failed to compile: {compile_proc.stderr}"
        )
        run_and_check(
            compiled_trigger, expected_args, hidden_env, expected_output, trace_path
        )
    finally:
        shutil.copy2(backup, analyzer)
        os.chmod(analyzer, 0o755)
        for path in (backup, trace_path, compiled_trigger):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
