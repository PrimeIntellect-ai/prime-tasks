#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

APP_DIR = "/home/user/metrics_app"
HELPER_DIR = os.path.join(APP_DIR, "helper")
PROCESS_DATA_BIN = os.path.join(HELPER_DIR, "process_data")
DAEMON_FIXED_SCRIPT = os.path.join(APP_DIR, "daemon_fixed.sh")
LEGACY_SUBMITTER = os.path.join(APP_DIR, "legacy_submitter")


def test_process_data_compiled():
    assert os.path.isfile(PROCESS_DATA_BIN), f"The binary {PROCESS_DATA_BIN} was not compiled or is missing."
    assert os.access(PROCESS_DATA_BIN, os.X_OK), f"The binary {PROCESS_DATA_BIN} is not executable."


def test_process_data_is_rebuildable_and_functional():
    dry_run = subprocess.run(
        ["make", "-Bn"], cwd=HELPER_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stdout}"
    link_lines = [
        line for line in dry_run.stdout.splitlines()
        if re.search(r"(?:^|\s)(?:gcc|cc)(?:\s|$)", line) and "process_data" in line
    ]
    assert any(
        "-lm" in line and line.rfind("-lm") > max(line.find("process_data.c"), line.find(".o"))
        for line in link_lines
    ), "The Makefile does not link libm after the source/object input."

    if os.path.lexists(PROCESS_DATA_BIN):
        os.unlink(PROCESS_DATA_BIN)
    build = subprocess.run(
        ["make", "-B"], cwd=HELPER_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert build.returncode == 0, f"Rebuilding process_data failed:\n{build.stdout}"
    assert os.path.isfile(PROCESS_DATA_BIN), "make did not recreate process_data."
    assert os.access(PROCESS_DATA_BIN, os.X_OK), "Rebuilt process_data is not executable."
    with open(PROCESS_DATA_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "process_data is not a compiled ELF executable."

    run = subprocess.run(
        [PROCESS_DATA_BIN], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert run.returncode == 0, f"process_data failed: {run.stderr}"
    assert re.fullmatch(r"Result:\s*4\.000000\s*", run.stdout), \
        f"process_data produced unexpected output: {run.stdout!r}"


def test_daemon_fixed_exists_and_executable():
    assert os.path.isfile(DAEMON_FIXED_SCRIPT), f"The fixed script {DAEMON_FIXED_SCRIPT} does not exist."
    assert os.access(DAEMON_FIXED_SCRIPT, os.X_OK), f"The fixed script {DAEMON_FIXED_SCRIPT} is not executable."


def test_daemon_fixed_auth_token():
    with open(DAEMON_FIXED_SCRIPT, 'r') as f:
        content = f.read()
    assert "SUBMIT_TOKEN" in content, "The environment variable SUBMIT_TOKEN is missing in daemon_fixed.sh."
    assert "ALPHA99" in content, "The expected token value 'ALPHA99' is missing in daemon_fixed.sh."


def test_daemon_fixed_math_formula():
    with open(DAEMON_FIXED_SCRIPT, 'r') as f:
        content = f.read()
    match = re.search(r'\(\s*\$?VAL1\s*\+\s*\$?VAL2\s*\)', content)
    assert match is not None, "The math formula in daemon_fixed.sh does not correctly group (VAL1 + VAL2) with parentheses."


def test_daemon_fixed_memory_leak():
    with open(DAEMON_FIXED_SCRIPT, 'r') as f:
        content = f.read()
    assert "LOG_CACHE+=" not in content, "The memory leak is not fixed: 'LOG_CACHE+=' is still present in daemon_fixed.sh."
    assert re.search(r'LOG_CACHE\s*=', content), "LOG_CACHE is not being assigned in daemon_fixed.sh."


def test_legacy_submitter_auth_behavior():
    clean_env = os.environ.copy()
    clean_env.pop("SUBMIT_TOKEN", None)
    unauth = subprocess.run(
        [LEGACY_SUBMITTER], env=clean_env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert unauth.returncode != 0 and "Auth Error" in unauth.stdout

    clean_env["SUBMIT_TOKEN"] = "ALPHA99"
    auth = subprocess.run(
        [LEGACY_SUBMITTER], env=clean_env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert auth.returncode == 0 and "Success" in auth.stdout


def _instrument_script(content, val1, val2):
    lines = content.splitlines()
    output = []
    loop_found = False
    for line in lines:
        if re.match(r'^\s*VAL1\s*=', line):
            output.append(f"    VAL1={val1}")
        elif re.match(r'^\s*VAL2\s*=', line):
            output.append(f"    VAL2={val2}")
        elif re.match(r'^\s*break\s*(?:#.*)?$', line):
            # The supplied daemon has a one-iteration testing break. The verifier
            # controls the iteration count so assignment behavior is observed repeatedly.
            output.append("    : # verifier removed testing break")
        elif re.match(r'^\s*sleep\s+[^#]+(?:#.*)?$', line):
            output.append("    : # verifier skipped delay")
        else:
            output.append(line)
            if re.match(r'^\s*while\s+(?:true|:)\s*;?\s*do\s*$', line):
                loop_found = True
                output.append('    __VERIFY_ITER=$(( ${__VERIFY_ITER:-0} + 1 ))')
                output.append('    if (( __VERIFY_ITER > 3 )); then break; fi')
    assert loop_found, "daemon_fixed.sh no longer contains its continuous while loop."
    return "\n".join(output) + "\n"


def test_daemon_executes_fixed_logic_and_submitter():
    syntax = subprocess.run(
        ["bash", "-n", DAEMON_FIXED_SCRIPT], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert syntax.returncode == 0, f"daemon_fixed.sh has invalid Bash syntax: {syntax.stderr}"

    with open(DAEMON_FIXED_SCRIPT, "r") as f:
        original = f.read()

    for val1, val2 in [(7, 12), (3, 9)]:
        expected = (val1 + val2) // 2
        instrumented = _instrument_script(original, val1, val2)
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as tmp:
            tmp.write(instrumented)
            tmp_path = tmp.name
        try:
            env = os.environ.copy()
            env.pop("SUBMIT_TOKEN", None)
            run = subprocess.run(
                ["bash", "-x", tmp_path], env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
            )
        finally:
            os.unlink(tmp_path)

        trace = run.stdout
        assert run.returncode == 0, f"daemon execution failed:\n{trace}"
        assert re.search(r'^\+ export SUBMIT_TOKEN(?:=|$)', trace, re.MULTILINE), \
            "daemon_fixed.sh does not export SUBMIT_TOKEN."
        assert len(re.findall(r'^\+ AVG=' + re.escape(str(expected)) + r'$', trace, re.MULTILINE)) >= 3, \
            f"The average was not computed from VAL1={val1} and VAL2={val2}. Trace:\n{trace}"

        cache_updates = [
            line for line in trace.splitlines()
            if line.startswith("+ LOG_CACHE=") and "Processed avg:" in line
        ]
        assert len(cache_updates) >= 3, "LOG_CACHE was not updated on each loop iteration."
        assert all(line.count("Processed avg:") == 1 and str(expected) in line for line in cache_updates), \
            "LOG_CACHE does not retain only the latest correctly computed entry."
        assert len(re.findall(r'^\+ /home/user/metrics_app/legacy_submitter(?:\s|$)', trace, re.MULTILINE)) >= 3, \
            "daemon_fixed.sh did not invoke the legacy submitter each iteration."
        assert trace.count("Success") >= 3, \
            "The invoked legacy submitter did not receive valid authentication."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
