#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import resource
import secrets
import subprocess

SOURCE = "/home/user/log_analyzer.c"
EXECUTABLE = "/home/user/log_analyzer"
LOG = "/home/user/system_logs.dat"
TEMPLATE = "/home/user/report_template.txt"
REPORT = "/home/user/anomaly_report.txt"


def run_analyzer(memory_limit=None, timeout=45):
    def limit_memory():
        if memory_limit is not None:
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))

    return subprocess.run(
        [EXECUTABLE],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=limit_memory if memory_limit is not None else None,
    )


def test_c_source_compiles_to_executable():
    assert os.path.isfile(SOURCE), f"Missing C source file: {SOURCE}"
    assert not os.path.islink(SOURCE), f"C source must be a real file: {SOURCE}"
    if os.path.lexists(EXECUTABLE):
        os.unlink(EXECUTABLE)

    result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "The required gcc compilation failed:\n" +
        result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(EXECUTABLE), f"Compilation did not create {EXECUTABLE}"
    assert not os.path.islink(EXECUTABLE), f"Executable must be a real file: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"Compiled file is not executable: {EXECUTABLE}"


def test_compiled_program_streams_and_uses_template():
    original_log = open(LOG, "rb").read()
    original_template = open(TEMPLATE, "rb").read()
    token = secrets.token_hex(16)
    custom_template = (
        f"Verifier Template {token}\n"
        "First Anomaly Detected At: {{FIRST_ANOMALY_TIMESTAMP}}\n"
        "Total Errors Logged: {{TOTAL_ERRORS}}\n"
        f"Footer must remain unchanged: {token}\n"
    )

    expected_first = None
    total_errors = 0
    window = []
    count = 1_100_000

    try:
        with open(LOG, "wb") as f:
            for i in range(count):
                ts = 1700000000 + i
                is_error = (30 <= i < 50) or (i >= 1000 and i % 10000 == 0)
                if is_error:
                    msg = b"ERROR Connection failed with padding 0123456789."
                    total_errors += 1
                else:
                    msg = b"INFO System running normal with padding 0123456789."

                window.append(is_error)
                if len(window) > 100:
                    window.pop(0)
                if expected_first is None and sum(window) >= 20:
                    expected_first = str(ts)

                ts_bytes = str(ts).encode("ascii")
                # These bytes must disappear before timestamp and marker parsing.
                raw = b"[" + ts_bytes[:4] + b"\x01" + ts_bytes[4:] + b"]\xff " + msg + b"\n"
                f.write(raw)

        with open(TEMPLATE, "w", encoding="ascii") as f:
            f.write(custom_template)
        if os.path.lexists(REPORT):
            os.unlink(REPORT)

        # The generated input is larger than this address-space limit. A program
        # that loads the entire file cannot pass, while a line-streaming C program can.
        result = run_analyzer(memory_limit=48 * 1024 * 1024)
        assert result.returncode == 0, (
            "The compiled analyzer failed on the streaming test:\n" +
            result.stderr.decode("utf-8", errors="replace")
        )
        assert os.path.isfile(REPORT), "The compiled analyzer did not generate anomaly_report.txt"
        assert os.path.getsize(REPORT) < 1024 * 1024, "Generated report is unexpectedly large"

        with open(REPORT, "r", encoding="ascii") as f:
            actual = f.read()
        expected = custom_template.replace(
            "{{FIRST_ANOMALY_TIMESTAMP}}", expected_first or "NONE"
        ).replace("{{TOTAL_ERRORS}}", str(total_errors))
        assert actual == expected, (
            "The report must be the supplied template with both placeholders replaced exactly"
        )
        with open(TEMPLATE, "r", encoding="ascii") as f:
            assert f.read() == custom_template, "The analyzer modified the input template"
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log)
        with open(TEMPLATE, "wb") as f:
            f.write(original_template)
        if os.path.lexists(REPORT):
            os.unlink(REPORT)
        # Regenerate the required final artifact from the original task inputs.
        result = run_analyzer(timeout=30)
        assert result.returncode == 0, (
            "The compiled analyzer failed on the original inputs:\n" +
            result.stderr.decode("utf-8", errors="replace")
        )


def compute_truth():
    log_path = '/home/user/system_logs.dat'
    assert os.path.exists(log_path), f"Missing file: {log_path}"

    with open(log_path, 'rb') as f:
        raw_data = f.read()

    sanitized_chars = []
    for b in raw_data:
        if 0x20 <= b <= 0x7E or b == 0x0A or b == 0x0D:
            sanitized_chars.append(chr(b))

    sanitized_text = "".join(sanitized_chars)
    lines = sanitized_text.splitlines()

    total_errors = 0
    first_anomaly_ts = None
    window = []

    for line in lines:
        if not line:
            continue
        is_error = "] ERROR " in line
        if is_error:
            total_errors += 1

        window.append(is_error)
        if len(window) > 100:
            window.pop(0)

        if sum(window) >= 20 and first_anomaly_ts is None:
            m = re.search(r'\[(\d+)\]', line)
            if m:
                first_anomaly_ts = m.group(1)

    if first_anomaly_ts is None:
        first_anomaly_ts = "NONE"

    return str(first_anomaly_ts), str(total_errors)


def test_anomaly_report_generated_and_correct():
    report_path = "/home/user/anomaly_report.txt"
    assert os.path.exists(report_path), f"Missing file: {report_path}. Did you run the C program?"

    expected_ts, expected_errors = compute_truth()

    with open(report_path, 'r') as f:
        content = f.read()

    assert f"First Anomaly Detected At: {expected_ts}" in content, (
        f"Expected to find 'First Anomaly Detected At: {expected_ts}' in {report_path}. "
        "Check your sliding window logic and sanitization."
    )

    assert f"Total Errors Logged: {expected_errors}" in content, (
        f"Expected to find 'Total Errors Logged: {expected_errors}' in {report_path}. "
        "Check your error counting logic."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
