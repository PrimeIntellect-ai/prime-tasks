#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import pytest

PARSE_PATH = "/home/user/parse_linker.py"
LOG_PATH = "/home/user/linker_error.log"
JSON_PATH = "/home/user/missing_symbols.json"
BENCHMARK_PATH = "/home/user/benchmark.sh"
BENCHMARK_LOG_PATH = "/home/user/benchmark.log"

EXPECTED_DATA = {
    "ui_module.o": [
        {"file": "ui_module.c", "symbol": "draw_rect"},
        {"file": "ui_module.c", "symbol": "fill_color"}
    ],
    "network.o": [
        {"file": "network.c", "symbol": "ssl_connect"},
        {"file": "network.c", "symbol": "ssl_read"}
    ],
    "core.o": [
        {"file": "core.c", "symbol": "hardware_init"}
    ]
}


def run_parser():
    result = subprocess.run(
        ["python3", PARSE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{PARSE_PATH} failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), f"{PARSE_PATH} did not create {JSON_PATH}"
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{PARSE_PATH} produced invalid JSON: {exc}")


def test_parse_linker_exists():
    path = PARSE_PATH
    assert os.path.exists(path), f"{path} does not exist"
    assert os.path.isfile(path), f"{path} is not a file"


def test_parser_executes_on_original_log():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    data = run_parser()
    assert data == EXPECTED_DATA, (
        f"Executing {PARSE_PATH} did not derive the expected data from {LOG_PATH}"
    )


def test_parser_tracks_current_object_on_unseen_input():
    token = secrets.token_hex(8)
    obj1 = f"alpha_{token}.o"
    obj2 = f"beta_{token}.o"
    src1 = f"alpha_{token}.c"
    src2 = f"beta_{token}.c"
    symbols1 = [f"first_{token}", f"second_{token}", f"third_{token}"]
    symbols2 = [f"fourth_{token}", f"fifth_{token}"]

    generated_log = (
        f"compiler: harmless diagnostic {token}\n"
        f"/usr/bin/ld: {obj1}: in function `func_a':\n"
        f"{src1}:(.text+0x10): undefined reference to `{symbols1[0]}'\n"
        f"/usr/bin/ld: {src1}:(.text+0x20): undefined reference to `{symbols1[1]}'\n"
        f"{src1}:(.text+0x30): undefined reference to `{symbols1[2]}'\n"
        f"/usr/bin/ld: {obj2}: in function `func_b':\n"
        f"{src2}:(.text+0x40): undefined reference to `{symbols2[0]}'\n"
        f"/usr/bin/ld: {src2}:(.text+0x50): undefined reference to `{symbols2[1]}'\n"
        "collect2: error: ld returned 1 exit status\n"
    )
    expected = {
        obj1: [{"file": src1, "symbol": symbol} for symbol in symbols1],
        obj2: [{"file": src2, "symbol": symbol} for symbol in symbols2],
    }

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()
    try:
        with open(LOG_PATH, "w") as f:
            f.write(generated_log)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        actual = run_parser()
        assert actual == expected, (
            "The parser did not associate multiple undefined references with "
            "the current object file on dynamically generated input"
        )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        if os.path.isfile(PARSE_PATH):
            run_parser()


def test_benchmark_sh():
    path = BENCHMARK_PATH
    assert os.path.exists(path), f"{path} does not exist"
    assert os.path.isfile(path), f"{path} is not a file"

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable"

    with open(path, "r") as f:
        content = f.read()

    assert "50" in content, f"{path} does not contain a loop of 50"
    assert "time " in content, f"{path} does not use the 'time' command"
    assert "parse_linker.py" in content, f"{path} does not run parse_linker.py"
    assert "/usr/bin/time" not in content, f"{path} must use the shell built-in time command"


def test_benchmark_really_runs_parser_fifty_times_and_records_timing():
    parser_backup = "/tmp/parse_linker_agent_backup.py"
    count_path = f"/tmp/parser_count_{secrets.token_hex(8)}"
    shutil.copy2(PARSE_PATH, parser_backup)

    wrapper = '''#!/usr/bin/env python3
import json
import os
count_path = os.environ["PARSER_COUNT_FILE"]
with open(count_path, "a") as count_file:
    count_file.write("1\\n")
with open("/home/user/missing_symbols.json", "w") as output:
    json.dump({}, output)
'''

    try:
        with open(PARSE_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(PARSE_PATH, 0o755)
        if os.path.exists(BENCHMARK_LOG_PATH):
            os.remove(BENCHMARK_LOG_PATH)

        env = os.environ.copy()
        env["PARSER_COUNT_FILE"] = count_path
        result = subprocess.run(
            ["bash", BENCHMARK_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"Executing {BENCHMARK_PATH} failed with exit code "
            f"{result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(count_path), f"{BENCHMARK_PATH} never ran parse_linker.py"
        with open(count_path, "r") as f:
            executions = len(f.readlines())
        assert executions == 50, (
            f"{BENCHMARK_PATH} ran parse_linker.py {executions} times instead of 50"
        )

        assert os.path.isfile(BENCHMARK_LOG_PATH), (
            f"{BENCHMARK_PATH} did not create {BENCHMARK_LOG_PATH}"
        )
        with open(BENCHMARK_LOG_PATH, "r") as f:
            timing = f.read()
        assert timing.strip(), f"{BENCHMARK_LOG_PATH} is empty"
        assert re.search(r"(?m)^\s*(real|user|sys)\s+", timing), (
            f"{BENCHMARK_LOG_PATH} does not contain timing data from the shell time command"
        )
    finally:
        shutil.copy2(parser_backup, PARSE_PATH)
        if os.path.exists(parser_backup):
            os.remove(parser_backup)
        if os.path.exists(count_path):
            os.remove(count_path)
        if os.path.isfile(PARSE_PATH):
            run_parser()


def test_missing_symbols_json():
    path = JSON_PATH
    assert os.path.exists(path), f"{path} does not exist"
    assert os.path.isfile(path), f"{path} is not a file"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON")

    expected_data = EXPECTED_DATA
    assert data == expected_data, f"The contents of {path} do not match the expected structured data"


def test_benchmark_log():
    path = BENCHMARK_LOG_PATH
    assert os.path.exists(path), f"{path} does not exist. Did you run benchmark.sh and redirect standard error?"
    assert os.path.isfile(path), f"{path} is not a file"

    with open(path, "r") as f:
        content = f.read()

    assert len(content.strip()) > 0, f"{path} is empty"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
