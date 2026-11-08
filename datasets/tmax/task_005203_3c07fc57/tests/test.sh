#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

RECOVERED_LOG_PATH = "/home/user/recovered.log"
PARSER_C_PATH = "/home/user/parser.c"
PARSER_BIN_PATH = "/home/user/parser"
SCRIPT_PATH = "/home/user/regression_test.sh"

EXPECTED_LOG_CONTENT = "IP: 192.168.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1 USER: admin\n"


def run(command, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(command, **kwargs)


def test_recovered_log_content():
    """Verify the contents of the recovered log file."""
    assert os.path.exists(RECOVERED_LOG_PATH), f"Recovered log not found at {RECOVERED_LOG_PATH}"
    with open(RECOVERED_LOG_PATH, "r") as f:
        content = f.read()
    assert content == EXPECTED_LOG_CONTENT, "The contents of the recovered log do not match the expected deleted data."


def test_regression_test_script():
    """Verify that the script really compiles parser.c and runs the result on recovered.log."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"

    # Retain the original check on the submitted parser and recovered log.
    result = run([SCRIPT_PATH])
    assert result.returncode == 0, f"Regression test script failed with exit code {result.returncode}. Stderr: {result.stderr}"

    # Replace the source briefly with a runtime-generated probe. The marker can
    # only be created if the script compiles this source and executes the new
    # /home/user/parser with /home/user/recovered.log as its input argument.
    nonce = secrets.token_hex(16)
    marker = f"/tmp/regression_probe_{nonce}"
    probe_content = f"probe-{nonce}\\n"
    probe_source = r'''#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    char buf[256] = {0};
    if (argc != 2 || strcmp(argv[1], "/home/user/recovered.log") != 0) return 41;
    FILE *in = fopen(argv[1], "r");
    if (!in) return 42;
    if (!fgets(buf, sizeof(buf), in)) { fclose(in); return 43; }
    fclose(in);
    if (strcmp(buf, "CONTENT_TOKEN") != 0) return 44;
    FILE *out = fopen("MARKER_PATH", "w");
    if (!out) return 45;
    fputs("NONCE_TOKEN", out);
    fclose(out);
    return 0;
}
'''.replace("CONTENT_TOKEN", probe_content.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    probe_source = probe_source.replace("MARKER_PATH", marker).replace("NONCE_TOKEN", nonce)

    with open(PARSER_C_PATH, "rb") as f:
        source_backup = f.read()
    with open(RECOVERED_LOG_PATH, "rb") as f:
        log_backup = f.read()
    binary_existed = os.path.exists(PARSER_BIN_PATH)
    binary_backup = None
    binary_mode = None
    if binary_existed:
        with open(PARSER_BIN_PATH, "rb") as f:
            binary_backup = f.read()
        binary_mode = os.stat(PARSER_BIN_PATH).st_mode

    try:
        with open(PARSER_C_PATH, "w") as f:
            f.write(probe_source)
        with open(RECOVERED_LOG_PATH, "w") as f:
            f.write(probe_content)
        if os.path.exists(PARSER_BIN_PATH):
            os.remove(PARSER_BIN_PATH)

        probe_result = run([SCRIPT_PATH])
        assert probe_result.returncode == 0, (
            f"Regression script failed its compile-and-run probe: {probe_result.stderr}"
        )
        assert os.path.exists(PARSER_BIN_PATH), "Regression script did not compile /home/user/parser"
        assert os.path.exists(marker), (
            "Regression script did not execute the parser it compiled against /home/user/recovered.log"
        )
        with open(marker, "r") as f:
            assert f.read() == nonce, "Regression probe marker was invalid"
    finally:
        with open(PARSER_C_PATH, "wb") as f:
            f.write(source_backup)
        with open(RECOVERED_LOG_PATH, "wb") as f:
            f.write(log_backup)
        if os.path.exists(marker):
            os.remove(marker)
        if binary_existed:
            with open(PARSER_BIN_PATH, "wb") as f:
                f.write(binary_backup)
            os.chmod(PARSER_BIN_PATH, binary_mode)
        elif os.path.exists(PARSER_BIN_PATH):
            os.remove(PARSER_BIN_PATH)


def test_parser_fixed():
    """Verify the parser compiles, retains real parsing behavior, and is memory-safe on edge cases."""
    assert os.path.exists(PARSER_C_PATH), f"Source file not found at {PARSER_C_PATH}"

    # Retain the original direct compilation and recovered-log execution checks.
    compile_result = run(["gcc", "-o", PARSER_BIN_PATH, PARSER_C_PATH])
    assert compile_result.returncode == 0, f"Compilation failed: {compile_result.stderr}"
    assert os.path.exists(PARSER_BIN_PATH), f"Compiled binary not found at {PARSER_BIN_PATH}"

    run_result = run([PARSER_BIN_PATH, RECOVERED_LOG_PATH])
    assert run_result.returncode == 0, (
        f"Parser crashed or failed with exit code {run_result.returncode}. It may still be vulnerable to buffer overflow."
    )

    # Exercise actual parsing with values generated only when verification runs,
    # so a no-op main or fixed-output replacement cannot satisfy the check.
    ip1 = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}.7"
    ip2 = f"172.16.{secrets.randbelow(200) + 1}.9"
    user1 = "u" + secrets.token_hex(5)
    user2 = "v" + secrets.token_hex(5)
    valid_data = (
        f"IP: {ip1} USER: {user1}\n"
        "this is not a log record\n"
        f"IP: {ip2} USER: {user2}\n"
    )
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(valid_data)
        valid_path = f.name
    try:
        parsed = run([PARSER_BIN_PATH, valid_path])
        assert parsed.returncode == 0, f"Parser failed on valid records: {parsed.stderr}"
        assert parsed.stdout == f"Parsed IP: {ip1}\nParsed IP: {ip2}\n", (
            "Parser did not parse valid log records correctly"
        )
    finally:
        os.unlink(valid_path)

    # Build with memory-safety instrumentation and test independently generated
    # overlong IP and user fields in addition to the recovered crashing record.
    sanitized_bin = f"/tmp/parser_sanitized_{secrets.token_hex(8)}"
    sanitize_compile = run([
        "gcc", "-O0", "-g", "-fno-omit-frame-pointer",
        "-fsanitize=address,undefined", "-o", sanitized_bin, PARSER_C_PATH
    ])
    assert sanitize_compile.returncode == 0, f"Sanitized compilation failed: {sanitize_compile.stderr}"

    long_ip = "1." * (300 + secrets.randbelow(100))
    long_user = "user_" + secrets.token_hex(300)
    edge_data = EXPECTED_LOG_CONTENT + f"IP: {long_ip} USER: ok\nIP: 127.0.0.1 USER: {long_user}\n"
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(edge_data)
        edge_path = f.name
    try:
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        safe_run = run([sanitized_bin, edge_path], env=env)
        assert safe_run.returncode == 0, (
            f"Parser is not safe on overlong fields (exit {safe_run.returncode}): {safe_run.stderr}"
        )
        assert "AddressSanitizer" not in safe_run.stderr and "runtime error:" not in safe_run.stderr, (
            f"Memory-safety instrumentation detected an error: {safe_run.stderr}"
        )
    finally:
        if os.path.exists(edge_path):
            os.unlink(edge_path)
        if os.path.exists(sanitized_bin):
            os.unlink(sanitized_bin)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
