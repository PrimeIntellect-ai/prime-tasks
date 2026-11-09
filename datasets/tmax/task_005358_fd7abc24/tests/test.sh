#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

TESTER_DIR = Path("/home/user/tester")
PAYLOAD_PATH = Path("/home/user/bypass_payload.txt")
LINUX_ENDPOINT = "https://linux.gateway.local/api"
WINDOWS_ENDPOINT = "https://win.gateway.local/api"
ORIGINAL_RULE = b'ALLOW_IF: LEN == 10 AND PREFIX == "TST_" AND SUM_DIGITS == 10'
MUTATED_RULE = b'ALLOW_IF: LEN == 10 AND PREFIX == "ALT_" AND SUM_DIGITS == 11'


def run(cmd, *, cwd=None, env=None, timeout=60):
    result = subprocess.run(
        cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(map(str, cmd))}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def read_and_validate_payload(prefix="TST_", digit_sum=10):
    assert PAYLOAD_PATH.exists(), f"{PAYLOAD_PATH} does not exist"
    raw = PAYLOAD_PATH.read_text()
    payload = raw.strip()
    assert payload, "Payload is empty"
    assert "\x00" not in raw, "Payload contains a NUL byte"
    assert len(payload) == 10, (
        f"Payload '{payload}' length is not 10 (length is {len(payload)})"
    )
    assert payload.startswith(prefix), (
        f"Payload '{payload}' does not start with '{prefix}'"
    )
    total = sum(int(c) for c in payload if c.isdigit())
    assert total == digit_sum, (
        f"Sum of digits in payload '{payload}' is {total}, expected {digit_sum}"
    )
    return payload


def execute_and_check(binary, prefix, digit_sum, endpoint):
    if PAYLOAD_PATH.exists():
        PAYLOAD_PATH.unlink()
    result = run([str(binary)], cwd=TESTER_DIR, timeout=20)
    assert endpoint in result.stdout.splitlines(), (
        f"Program did not print Endpoint {endpoint!r}; stdout was {result.stdout!r}"
    )
    return read_and_validate_payload(prefix, digit_sum)


def test_program_behavior_parser_solver_and_conditional_endpoints():
    assert TESTER_DIR.is_dir(), f"{TESTER_DIR} directory does not exist"
    go_mod = TESTER_DIR / "go.mod"
    assert go_mod.is_file(), f"{go_mod} does not exist"
    assert re.search(r"(?m)^\s*module\s+waf_tester\s*$", go_mod.read_text()), (
        "go.mod does not declare module waf_tester"
    )

    base_env = os.environ.copy()
    base_env["CGO_ENABLED"] = "0"
    host_arch = run(["go", "env", "GOHOSTARCH"]).stdout.strip()

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        native = td / "tester_native"
        rebuilt_arm = td / "tester_arm64"
        rebuilt_windows = td / "tester_amd64.exe"

        linux_env = base_env.copy()
        linux_env.update({"GOOS": "linux", "GOARCH": host_arch})
        arm_env = base_env.copy()
        arm_env.update({"GOOS": "linux", "GOARCH": "arm64"})
        windows_env = base_env.copy()
        windows_env.update({"GOOS": "windows", "GOARCH": "amd64"})

        run(["go", "build", "-o", str(native), "."], cwd=TESTER_DIR, env=linux_env)
        run(["go", "build", "-o", str(rebuilt_arm), "."], cwd=TESTER_DIR, env=arm_env)
        run(["go", "build", "-o", str(rebuilt_windows), "."], cwd=TESTER_DIR, env=windows_env)

        linux_doc = run(["go", "doc", ".", "Endpoint"], cwd=TESTER_DIR, env=linux_env).stdout
        windows_doc = run(["go", "doc", ".", "Endpoint"], cwd=TESTER_DIR, env=windows_env).stdout
        assert re.search(r"\bvar\s+Endpoint\b", linux_doc), "Linux build does not define global variable Endpoint"
        assert re.search(r"\bvar\s+Endpoint\b", windows_doc), "Windows build does not define global variable Endpoint"

        arm_data = rebuilt_arm.read_bytes()
        windows_data = rebuilt_windows.read_bytes()
        assert LINUX_ENDPOINT.encode() in arm_data, "Rebuilt Linux ARM64 program lacks the Linux Endpoint"
        assert WINDOWS_ENDPOINT.encode() not in arm_data, "Linux build includes the Windows Endpoint"
        assert WINDOWS_ENDPOINT.encode() in windows_data, "Rebuilt Windows AMD64 program lacks the Windows Endpoint"
        assert LINUX_ENDPOINT.encode() not in windows_data, "Windows build includes the Linux Endpoint"

        execute_and_check(native, "TST_", 10, LINUX_ENDPOINT)

        data = native.read_bytes()
        assert ORIGINAL_RULE in data, (
            "The compiled program does not contain the specified WAF DSL rule to parse"
        )
        assert len(ORIGINAL_RULE) == len(MUTATED_RULE)
        native.write_bytes(data.replace(ORIGINAL_RULE, MUTATED_RULE))

        try:
            execute_and_check(native, "ALT_", 11, LINUX_ENDPOINT)
        finally:
            # Restore the required final payload using the unmodified source build.
            run(["go", "build", "-o", str(native), "."], cwd=TESTER_DIR, env=linux_env)
            execute_and_check(native, "TST_", 10, LINUX_ENDPOINT)


def test_bypass_payload():
    read_and_validate_payload("TST_", 10)


def test_tester_arm64_binary():
    binary_path = Path("/home/user/tester_arm64")
    assert binary_path.exists(), f"{binary_path} does not exist"
    result = subprocess.run(["file", str(binary_path)], capture_output=True, text=True)
    assert "ARM aarch64" in result.stdout, (
        f"{binary_path} is not an ARM aarch64 binary. file output: {result.stdout}"
    )
    data = binary_path.read_bytes()
    assert LINUX_ENDPOINT.encode() in data, "Submitted ARM64 binary lacks the Linux Endpoint"
    assert ORIGINAL_RULE in data, "Submitted ARM64 binary lacks the WAF DSL rule"


def test_tester_amd64_binary():
    binary_path = Path("/home/user/tester_amd64.exe")
    assert binary_path.exists(), f"{binary_path} does not exist"
    result = subprocess.run(["file", str(binary_path)], capture_output=True, text=True)
    assert "PE32+" in result.stdout and "x86-64" in result.stdout, (
        f"{binary_path} is not a Windows AMD64 binary. file output: {result.stdout}"
    )
    data = binary_path.read_bytes()
    assert WINDOWS_ENDPOINT.encode() in data, "Submitted Windows binary lacks the Windows Endpoint"
    assert ORIGINAL_RULE in data, "Submitted Windows binary lacks the WAF DSL rule"


def test_build_tags():
    assert TESTER_DIR.exists() and TESTER_DIR.is_dir(), f"{TESTER_DIR} directory does not exist"
    go_files = [f for f in os.listdir(TESTER_DIR) if f.endswith(".go")]
    assert len(go_files) > 0, f"No .go files found in {TESTER_DIR}"

    has_linux_tag = False
    has_windows_tag = False
    linux_pattern = re.compile(r'//\s*go:build\s+.*linux|//\s*\+build\s+.*linux')
    windows_pattern = re.compile(r'//\s*go:build\s+.*windows|//\s*\+build\s+.*windows')

    for go_file in go_files:
        content = (TESTER_DIR / go_file).read_text()
        if linux_pattern.search(content):
            has_linux_tag = True
        if windows_pattern.search(content):
            has_windows_tag = True

    assert has_linux_tag, "No Go source file contains a Linux build tag"
    assert has_windows_tag, "No Go source file contains a Windows build tag"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
