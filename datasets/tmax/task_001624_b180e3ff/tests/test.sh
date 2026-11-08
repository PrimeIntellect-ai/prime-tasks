#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import stat
import string
import subprocess
import tempfile

import pytest

HOME_DIR = "/home/user"
PROCESSOR_C = os.path.join(HOME_DIR, "processor.c")
MAKEFILE = os.path.join(HOME_DIR, "Makefile")
CI_PIPELINE = os.path.join(HOME_DIR, "ci_pipeline.sh")
RESULT_JSON = os.path.join(HOME_DIR, "result.json")
CI_STATUS = os.path.join(HOME_DIR, "ci_status.log")
PROCESSOR_BIN = os.path.join(HOME_DIR, "processor")
TEST_DATA = os.path.join(HOME_DIR, "test_data.csv")
WEBSOCAT = os.path.join(HOME_DIR, "websocat")

EXPECTED_DATA = (
    "dev_alpha,16.0\n"
    "dev_beta,25.0\n"
    "dev_alpha,20.0\n"
    "dev_gamma,100.0\n"
)
EXPECTED_RESULT = '{"top_id": "dev_gamma", "max_sqrt": 10.00}'
DOWNLOAD_COMMAND = (
    "wget -q https://github.com/vi/websocat/releases/download/v1.11.0/"
    "websocat.x86_64-unknown-linux-musl -O ./websocat && chmod +x ./websocat"
)


def test_files_exist():
    """Verify that all required files exist."""
    assert os.path.isfile(PROCESSOR_C), f"File {PROCESSOR_C} does not exist."
    assert os.path.isfile(MAKEFILE), f"File {MAKEFILE} does not exist."
    assert os.path.isfile(CI_PIPELINE), f"File {CI_PIPELINE} does not exist."
    assert os.path.isfile(RESULT_JSON), f"File {RESULT_JSON} does not exist."
    assert os.path.isfile(CI_STATUS), f"File {CI_STATUS} does not exist."


def test_ci_pipeline_executable():
    """Verify that the CI pipeline script is executable."""
    assert os.path.isfile(CI_PIPELINE), f"File {CI_PIPELINE} does not exist."
    st = os.stat(CI_PIPELINE)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {CI_PIPELINE} is not executable."


def test_makefile_links_math():
    """Verify that the Makefile links the math library (-lm)."""
    assert os.path.isfile(MAKEFILE), f"File {MAKEFILE} does not exist."
    with open(MAKEFILE, "r") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not link the math library (-lm)."


def test_ci_status_success():
    """Verify that ci_status.log indicates success."""
    assert os.path.isfile(CI_STATUS), f"File {CI_STATUS} does not exist."
    with open(CI_STATUS, "r") as f:
        content = f.read().strip()
    assert "CI PIPELINE SUCCESS" in content, f"ci_status.log does not contain 'CI PIPELINE SUCCESS'. Found: {content}"


def test_result_json_content():
    """Verify that result.json contains the correct expected output."""
    assert os.path.isfile(RESULT_JSON), f"File {RESULT_JSON} does not exist."
    with open(RESULT_JSON, "r") as f:
        content = f.read().strip()

    expected_str = '{"top_id": "dev_gamma", "max_sqrt": 10.00}'
    assert expected_str in content, f"result.json does not match exactly. Expected '{expected_str}', found '{content}'"


def test_make_clean_and_build():
    """Verify that make clean removes the binary, and make builds it again."""
    assert os.path.isfile(MAKEFILE), f"File {MAKEFILE} does not exist."
    os.chdir(HOME_DIR)

    result = subprocess.run(["make", "clean"], capture_output=True, text=True)
    assert result.returncode == 0, f"'make clean' failed with output: {result.stderr}"
    assert not os.path.exists(PROCESSOR_BIN), f"'make clean' did not remove {PROCESSOR_BIN}."

    result = subprocess.run(["make"], capture_output=True, text=True)
    assert result.returncode == 0, f"'make' failed with output: {result.stderr}"
    assert os.path.isfile(PROCESSOR_BIN), f"'make' did not create {PROCESSOR_BIN}."
    assert os.access(PROCESSOR_BIN, os.X_OK), f"{PROCESSOR_BIN} is not executable."


def test_processor_uses_math_and_processes_unseen_inputs():
    with open(PROCESSOR_C, "r") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]math\.h[>\"]", source), "processor.c does not include math.h"
    assert re.search(r"\bsqrt\s*\(", source), "processor.c does not call sqrt"

    build = subprocess.run(["make"], cwd=HOME_DIR, capture_output=True, text=True)
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(PROCESSOR_BIN) and os.access(PROCESSOR_BIN, os.X_OK)

    rng = random.SystemRandom()
    for _ in range(4):
        suffix = ''.join(rng.choice(string.ascii_lowercase) for _ in range(10))
        ids = [f"unit_{suffix}_{i}" for i in range(5)]
        rows = []
        sums = {}
        for i, device in enumerate(ids):
            a = rng.randint(1, 400)
            b = rng.randint(1, 400)
            if i == 3:
                b += 5000
            sums[device] = a + b
            rows.extend([(device, a), (device, b)])
        rng.shuffle(rows)
        input_text = ''.join(f"{device},{value}.0\n" for device, value in rows)
        top_id = max(sums, key=sums.get)
        expected = f'{{"top_id": "{top_id}", "max_sqrt": {math.sqrt(sums[top_id]):.2f}}}'

        run = subprocess.run(
            [PROCESSOR_BIN], input=input_text, cwd=HOME_DIR,
            capture_output=True, text=True, timeout=5
        )
        assert run.returncode == 0, run.stderr
        assert run.stdout.strip() == expected, (
            f"processor produced {run.stdout.strip()!r}; expected {expected!r} "
            f"for input {input_text!r}"
        )


def test_pipeline_source_contains_required_workflow():
    with open(CI_PIPELINE, "r") as f:
        script = f.read()

    assert DOWNLOAD_COMMAND in script, "ci_pipeline.sh does not contain the exact required download command"
    required_fragments = [
        "make clean",
        "make",
        "ws-listen:127.0.0.1:8080",
        "sleep 1",
        "ws://127.0.0.1:8080",
        "./processor",
        "/home/user/result.json",
    ]
    for fragment in required_fragments:
        assert fragment in script, f"ci_pipeline.sh is missing required workflow fragment: {fragment}"

    server_pos = script.find("ws-listen:127.0.0.1:8080")
    sleep_pos = script.find("sleep 1", server_pos)
    client_pos = script.find("ws://127.0.0.1:8080", sleep_pos)
    processor_pos = script.find("./processor", client_pos)
    assert -1 not in (server_pos, sleep_pos, client_pos, processor_pos), "WebSocket workflow is incomplete"
    assert server_pos < sleep_pos < client_pos < processor_pos, "WebSocket workflow is not in the required order"


def test_pipeline_executes_websocket_integration_workflow():
    with tempfile.TemporaryDirectory(prefix="pipeline-tools-") as tool_dir:
        tool_log = os.path.join(tool_dir, "tool.log")
        ws_state = os.path.join(tool_dir, "payload")
        fake_wget = os.path.join(tool_dir, "wget")

        wget_script = r'''#!/bin/bash
set -e
expected_url="https://github.com/vi/websocat/releases/download/v1.11.0/websocat.x86_64-unknown-linux-musl"
if [ "$#" -ne 4 ] || [ "$1" != "-q" ] || [ "$2" != "$expected_url" ] || [ "$3" != "-O" ] || [ "$4" != "./websocat" ]; then
    echo "unexpected wget arguments: $*" >&2
    exit 90
fi
echo "wget:$*" >> "$WS_LOG"
cat > "$4" <<'WS_EOF'
#!/bin/bash
set -e
if [ "$#" -eq 2 ] && [ "$1" = "-E" ] && [ "$2" = "ws-listen:127.0.0.1:8080" ]; then
    echo "server:$*" >> "$WS_LOG"
    tmp="${WS_STATE}.tmp.$$"
    cat > "$tmp"
    mv "$tmp" "$WS_STATE"
    exit 0
fi
if [ "$#" -eq 1 ] && [ "$1" = "ws://127.0.0.1:8080" ]; then
    echo "client:$*" >> "$WS_LOG"
    for i in $(seq 1 100); do
        [ -f "$WS_STATE" ] && break
        sleep 0.05
    done
    [ -f "$WS_STATE" ] || exit 91
    cat "$WS_STATE"
    exit 0
fi
echo "unexpected websocat arguments: $*" >&2
exit 92
WS_EOF
'''
        with open(fake_wget, "w") as f:
            f.write(wget_script)
        os.chmod(fake_wget, 0o755)

        for path in (RESULT_JSON, CI_STATUS, TEST_DATA, WEBSOCAT):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env["PATH"] = tool_dir + os.pathsep + env.get("PATH", "")
        env["WS_LOG"] = tool_log
        env["WS_STATE"] = ws_state

        run = subprocess.run(
            ["bash", "-x", CI_PIPELINE], cwd=HOME_DIR, env=env,
            capture_output=True, text=True, timeout=30
        )
        assert run.returncode == 0, f"pipeline failed:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"

        assert os.path.isfile(tool_log), "pipeline did not invoke the controlled wget/websocat workflow"
        with open(tool_log, "r") as f:
            calls = f.read()
        assert "wget:-q https://github.com/vi/websocat/releases/download/v1.11.0/websocat.x86_64-unknown-linux-musl -O ./websocat" in calls
        assert "server:-E ws-listen:127.0.0.1:8080" in calls, "pipeline did not start the WebSocket server"
        assert "client:ws://127.0.0.1:8080" in calls, "pipeline did not run the WebSocket client"

        trace = run.stderr
        assert re.search(r"(?m)^\+ make clean\s*$", trace), "pipeline did not execute make clean"
        assert re.search(r"(?m)^\+ make\s*$", trace), "pipeline did not execute make"
        assert re.search(r"(?m)^\+ sleep 1\s*$", trace), "pipeline did not execute sleep 1"
        assert re.search(r"(?m)^\+ ./processor\s*$", trace), "pipeline did not execute ./processor"

        with open(TEST_DATA, "r") as f:
            assert f.read() == EXPECTED_DATA, "pipeline did not create the exact required test_data.csv"
        with open(ws_state, "r") as f:
            assert f.read() == EXPECTED_DATA, "WebSocket server was not fed the required telemetry data"
        with open(RESULT_JSON, "r") as f:
            assert f.read().strip() == EXPECTED_RESULT
        with open(CI_STATUS, "r") as f:
            assert f.read().strip() == "CI PIPELINE SUCCESS"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
