#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import textwrap
import uuid

POISON_FILE = "/home/user/poison.txt"
MRE_FILE = "/home/user/mre.py"
EXPECTED_URL = "http://legacy.service.local/health?debug=memleak"


def test_poison_file_exists_and_correct():
    assert os.path.isfile(POISON_FILE), f"Expected file {POISON_FILE} does not exist."

    with open(POISON_FILE, "r") as f:
        content = f.read()

    assert content == EXPECTED_URL, (
        f"Contents of {POISON_FILE} are incorrect.\n"
        f"Expected: {EXPECTED_URL!r}\n"
        f"Got: {content!r}"
    )


def test_mre_script_exists_and_crashes():
    assert os.path.isfile(MRE_FILE), f"Expected file {MRE_FILE} does not exist."

    with open(MRE_FILE, "r") as f:
        source = f.read()

    tree = ast.parse(source, filename=MRE_FILE)
    module_aliases = set()
    function_aliases = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "monitor":
                    module_aliases.add(alias.asname or "monitor")
        elif isinstance(node, ast.ImportFrom) and node.module == "monitor":
            for alias in node.names:
                if alias.name == "check_uptime":
                    function_aliases.add(alias.asname or "check_uptime")

    assert module_aliases or function_aliases, (
        "mre.py must import monitor or check_uptime from monitor."
    )

    has_check_uptime_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if (
                node.func.attr == "check_uptime"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in module_aliases
            ):
                has_check_uptime_call = True
        elif isinstance(node.func, ast.Name) and node.func.id in function_aliases:
            has_check_uptime_call = True

    assert has_check_uptime_call, "mre.py must call monitor.check_uptime()."

    # Instrument the imported monitor module and execute the MRE to prove that
    # check_uptime is actually called with the exact poison URL.
    marker = "MRE_CALLS_" + uuid.uuid4().hex + ":"
    probe = textwrap.dedent(f"""
        import json
        import runpy
        import sys
        import types

        calls = []
        fake_monitor = types.ModuleType("monitor")

        def check_uptime(url):
            calls.append(url)
            raise MemoryError("probe")

        fake_monitor.check_uptime = check_uptime
        sys.modules["monitor"] = fake_monitor

        try:
            runpy.run_path({MRE_FILE!r}, run_name="__main__")
        except BaseException:
            pass

        print({marker!r} + json.dumps(calls))
    """)

    probe_result = subprocess.run(
        ["python3", "-c", probe],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=10,
    )

    call_lines = [
        line for line in probe_result.stdout.splitlines() if line.startswith(marker)
    ]
    assert call_lines, (
        "Executing mre.py did not produce evidence that monitor.check_uptime() was called."
    )
    calls = json.loads(call_lines[-1][len(marker):])
    assert EXPECTED_URL in calls, (
        "mre.py did not call monitor.check_uptime() with the exact crashing URL.\n"
        f"Observed arguments: {calls!r}"
    )

    # Run the MRE normally against the real compiled monitor module.
    env = os.environ.copy()
    env["PYTHONPATH"] = "/home/user"

    result = subprocess.run(
        ["python3", MRE_FILE],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode != 0, "Expected mre.py to crash (return non-zero exit code), but it succeeded."

    assert "MemoryError" in result.stderr, (
        "Expected mre.py to raise a MemoryError, but it did not.\n"
        f"Standard Error output:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
