#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_BINARY=/app/router_engine_stripped.real_for_verifier
CALL_LOG=/tmp/router_fuzzer_calls.jsonl

restore_binary() {
    if [ -e "$REAL_BINARY" ]; then
        rm -f /app/router_engine_stripped
        mv "$REAL_BINARY" /app/router_engine_stripped
    fi
}
trap restore_binary EXIT

mv /app/router_engine_stripped "$REAL_BINARY"
cat << 'WRAPPER_EOF' > /app/router_engine_stripped
#!/usr/bin/python3
import json
import os
import sys

real_binary = "/app/router_engine_stripped.real_for_verifier"
url = sys.argv[1] if len(sys.argv) > 1 else None
with open("/tmp/router_fuzzer_calls.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps(url, ensure_ascii=True) + "\n")
os.execv(real_binary, [real_binary] + sys.argv[1:])
WRAPPER_EOF
chmod 755 /app/router_engine_stripped
: > "$CALL_LOG"
chmod 666 "$CALL_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess


def imported_usage(tree):
    hypothesis_modules = set()
    hypothesis_names = set()
    subprocess_modules = set()
    subprocess_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                local = alias.asname or alias.name.split(".")[0]
                if alias.name == "hypothesis" or alias.name.startswith("hypothesis."):
                    hypothesis_modules.add(local)
                if alias.name == "subprocess":
                    subprocess_modules.add(local)
        elif isinstance(node, ast.ImportFrom):
            if node.module == "hypothesis" or (node.module and node.module.startswith("hypothesis.")):
                for alias in node.names:
                    hypothesis_names.add(alias.asname or alias.name)
            if node.module == "subprocess":
                for alias in node.names:
                    subprocess_names.add(alias.asname or alias.name)

    uses_hypothesis = False
    uses_subprocess = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name):
            uses_hypothesis |= func.id in hypothesis_names
            uses_subprocess |= func.id in subprocess_names
        elif isinstance(func, ast.Attribute):
            root = func.value
            while isinstance(root, ast.Attribute):
                root = root.value
            if isinstance(root, ast.Name):
                uses_hypothesis |= root.id in hypothesis_modules or root.id in hypothesis_names
                uses_subprocess |= root.id in subprocess_modules

    return uses_hypothesis, uses_subprocess


def test_fuzzing_results():
    script = "/home/user/fuzz_router.py"
    crash_log = "/home/user/crashes.log"
    binary = "/app/router_engine_stripped"
    ci_config = "/home/user/.github/workflows/fuzz.yml"
    call_log = "/tmp/router_fuzzer_calls.jsonl"

    assert os.path.isfile(script), f"Fuzzer script not found at {script}."
    with open(script, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "fuzz_router.py is empty."
    try:
        tree = ast.parse(source, filename=script)
    except SyntaxError as exc:
        raise AssertionError(f"fuzz_router.py is not valid Python: {exc}")

    uses_hypothesis, uses_subprocess = imported_usage(tree)
    assert uses_hypothesis, "fuzz_router.py must use Hypothesis to generate test inputs."
    assert uses_subprocess, "fuzz_router.py must use subprocess to invoke the router binary."

    assert os.path.exists(ci_config), f"CI config not found at {ci_config}."
    assert os.path.isfile(ci_config), f"CI config at {ci_config} is not a regular file."
    with open(ci_config, "r", encoding="utf-8") as f:
        workflow = f.read()
    workflow_lower = workflow.lower()
    assert workflow.strip(), "The CI workflow is empty."
    assert "actions/setup-python" in workflow_lower, "The workflow must set up Python."
    assert re.search(r"(?:pip(?:3)?\s+install|poetry\s+install|uv\s+sync)", workflow_lower), \
        "The workflow must install dependencies."
    assert "fuzz_router.py" in workflow, "The workflow must run fuzz_router.py."

    # Discard any pre-created answers and execute the submitted fuzzer itself.
    if os.path.exists(crash_log):
        os.remove(crash_log)
    open(call_log, "w").close()
    os.chmod(call_log, 0o666)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    try:
        run = subprocess.run(
            ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", script],
            cwd="/home/user",
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"fuzz_router.py did not complete within 120 seconds: {exc}")
    assert run.returncode == 0, (
        "fuzz_router.py failed when executed.\n"
        f"stdout:\n{run.stdout[-2000:]}\n"
        f"stderr:\n{run.stderr[-2000:]}"
    )

    assert os.path.exists(crash_log), f"{crash_log} not found. The fuzzer must create this file."

    with open(call_log, "r", encoding="utf-8") as f:
        invoked_urls = {json.loads(line) for line in f if line.strip()}
    invoked_urls.discard(None)
    assert invoked_urls, "The fuzzer did not invoke /app/router_engine_stripped."

    valid_crashes = 0
    with open(crash_log, "r") as f:
        urls = f.read().splitlines()

    # Every claimed crash must have been supplied to the binary by this fresh run.
    assert set(urls).issubset(invoked_urls), \
        "crashes.log contains URLs that the executed fuzzer never passed to the binary."

    # Test the discovered crashing URLs against the binary
    for url in set(urls):
        try:
            proc = subprocess.run([binary, url], capture_output=True, timeout=1)
            # Check for typical crash signals (e.g., -11 for SIGSEGV) or large exit codes
            if proc.returncode < 0 or proc.returncode > 127:
                valid_crashes += 1
        except subprocess.TimeoutExpired:
            pass

    assert valid_crashes >= 3, f"Found {valid_crashes} valid unique crashes, expected >= 3. Ensure the fuzzer explores edge cases like long parameters or missing keys."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    restore_binary
    trap - EXIT
    echo "1" > /logs/verifier/reward.txt
else
    restore_binary
    trap - EXIT
    echo "0" > /logs/verifier/reward.txt
fi
