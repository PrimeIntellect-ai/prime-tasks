#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shlex
import stat
import subprocess
import uuid
from pathlib import Path

import pytest

PIPELINE_DIR = Path("/home/user/pipeline")
PROCESS_SH = PIPELINE_DIR / "process.sh"
MAKEFILE = PIPELINE_DIR / "Makefile"
C_FILE = PIPELINE_DIR / "manifest_parser.c"
PAYLOAD = PIPELINE_DIR / "payload.dat"
OUTPUT_JSON = PIPELINE_DIR / "output.json"
EXECUTABLE = PIPELINE_DIR / "manifest_parser"

ORIGINAL_PAYLOAD = (
    "APP_NAME=SuperMobileApp\n"
    "BUILD_ID=99281\n"
    "MALICIOUS_INJECT=" + "A" * 127 + "\n"
)


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    assert PROCESS_SH.is_file(), f"{PROCESS_SH} does not exist."
    assert os.access(PROCESS_SH, os.X_OK), f"{PROCESS_SH} is not executable."

    PAYLOAD.write_text(ORIGINAL_PAYLOAD)
    if EXECUTABLE.exists():
        EXECUTABLE.unlink()

    build = subprocess.run(
        ["make"], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert EXECUTABLE.is_file(), "make did not build manifest_parser"
    assert os.access(EXECUTABLE, os.X_OK), "make did not create an executable parser"

    run = subprocess.run(
        [str(PROCESS_SH)], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert run.returncode == 0, f"process.sh failed:\n{run.stdout}\n{run.stderr}"


def test_process_sh_exists_and_executable():
    assert os.path.isfile(PROCESS_SH), f"{PROCESS_SH} does not exist."
    assert os.access(PROCESS_SH, os.X_OK), f"{PROCESS_SH} is not executable."


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"{MAKEFILE} does not exist."
    with open(MAKEFILE, "r") as f:
        content = f.read()

    assert "-Wall" in content, "Makefile does not contain the '-Wall' flag."
    assert "-o manifest_parser" in content or "manifest_parser:" in content, \
        "Makefile does not specify the output executable name 'manifest_parser'."


def test_c_code_fixed():
    assert os.path.isfile(C_FILE), f"{C_FILE} does not exist."
    with open(C_FILE, "r") as f:
        content = f.read()

    assert re.search(r"char\s+value\s*\[\s*128\s*\]\s*;", content), \
        "manifest_parser.c does not declare 'char value[128];'."
    assert re.search(r"%127s|%127\[", content), \
        "manifest_parser.c does not constrain the fscanf reading mechanism (e.g., %127s)."


def test_output_json_correct():
    assert os.path.isfile(OUTPUT_JSON), f"{OUTPUT_JSON} does not exist."
    with open(OUTPUT_JSON, "r") as f:
        content = f.read().strip()

    expected_lines = [
        '{"APP_NAME": "SuperMobileApp"}',
        '{"BUILD_ID": "99281"}',
        '{"MALICIOUS_INJECT": "' + 'A' * 127 + '"}'
    ]
    expected_content = "\n".join(expected_lines)
    assert content == expected_content, "output.json does not match the expected JSON output."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"The executable {EXECUTABLE} was not built."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."


def test_parser_on_derived_payload(tmp_path):
    values = {
        "RANDOM_KEY": uuid.uuid4().hex,
        "MAXIMUM_VALUE": "Z" * 127,
        "BUILD_NUMBER": str(int(uuid.uuid4().hex[:8], 16)),
    }
    payload = tmp_path / "dynamic.dat"
    payload.write_text("".join(f"{key}={value}\n" for key, value in values.items()))

    run = subprocess.run(
        [str(EXECUTABLE), str(payload)], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert run.returncode == 0, f"manifest_parser failed: {run.stderr}"

    lines = run.stdout.splitlines()
    assert len(lines) == len(values), "parser returned the wrong number of JSON lines"
    decoded = [json.loads(line) for line in lines]
    assert decoded == [{key: value} for key, value in values.items()]


def test_parser_is_memory_safe_on_oversized_input(tmp_path):
    sanitized = tmp_path / "manifest_parser_asan"
    compile_run = subprocess.run(
        ["gcc", "-Wall", "-fsanitize=address", "-fno-omit-frame-pointer",
         str(C_FILE), "-o", str(sanitized)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_run.returncode == 0, f"sanitized compilation failed: {compile_run.stderr}"

    malicious = tmp_path / "oversized.dat"
    malicious.write_text("ATTACK=" + "Q" * 5000 + "\n")
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    run = subprocess.run(
        [str(sanitized), str(malicious)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=10
    )
    assert run.returncode == 0, f"parser failed on malicious input: {run.stderr}"
    assert "AddressSanitizer" not in run.stderr, run.stderr
    for line in run.stdout.splitlines():
        json.loads(line)


def test_process_script_runs_make_and_parser_and_captures_stdout():
    nonce = uuid.uuid4().hex
    make_marker = PIPELINE_DIR / f".make_probe_{nonce}"
    args_marker = PIPELINE_DIR / f".args_probe_{nonce}"
    expected = ('{"WRAPPER_PROBE": "' + nonce + '"}\n').encode()

    saved = {}
    for path in (MAKEFILE, EXECUTABLE, PAYLOAD, OUTPUT_JSON):
        saved[path] = (path.exists(), path.read_bytes() if path.exists() else b"",
                       stat.S_IMODE(path.stat().st_mode) if path.exists() else 0)

    try:
        quoted_marker = shlex.quote(str(make_marker))
        MAKEFILE.write_text(
            ".PHONY: all manifest_parser clean\n"
            "all manifest_parser:\n"
            f"\t@printf made > {quoted_marker}\n"
            "clean:\n"
            "\t@:\n"
        )
        probe_script = (
            "#!/bin/bash\n"
            f"printf '%s\\0' \"$@\" > {shlex.quote(str(args_marker))}\n"
            f"printf '%s\\n' {shlex.quote(expected.decode().rstrip(chr(10)))}\n"
        )
        EXECUTABLE.write_text(probe_script)
        EXECUTABLE.chmod(0o755)
        PAYLOAD.write_text("PROBE=input\n")
        if OUTPUT_JSON.exists():
            OUTPUT_JSON.unlink()

        run = subprocess.run(
            [str(PROCESS_SH)], cwd=PIPELINE_DIR, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert run.returncode == 0, f"process.sh probe failed:\n{run.stdout}\n{run.stderr}"
        assert make_marker.is_file(), "process.sh did not run make"
        assert args_marker.is_file(), "process.sh did not execute ./manifest_parser"

        raw_args = args_marker.read_bytes().split(b"\0")
        args = [arg.decode() for arg in raw_args if arg]
        assert len(args) == 1 and Path(args[0]).name == "payload.dat", \
            "process.sh did not pass payload.dat as the parser's first and only argument"
        assert OUTPUT_JSON.is_file(), "process.sh did not create output.json"
        assert OUTPUT_JSON.read_bytes() == expected, \
            "process.sh did not capture the parser's standard output exactly"
    finally:
        for path, (existed, data, mode) in saved.items():
            if existed:
                path.write_bytes(data)
                path.chmod(mode)
            elif path.exists():
                path.unlink()
        for marker in (make_marker, args_marker):
            if marker.exists():
                marker.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
