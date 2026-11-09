#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import string
import subprocess

WORKSPACE_DIR = "/home/user/workspace"
REPORT_PATH = os.path.join(WORKSPACE_DIR, "report.txt")
FIXED_SOURCE_PATH = os.path.join(WORKSPACE_DIR, "fixed_login.c")
FIXED_CGI_PATH = os.path.join(WORKSPACE_DIR, "fixed_login.cgi")
AUDIT_LOG_PATH = os.path.join(WORKSPACE_DIR, "audit.log")
RECOMPILED_PATH = "/tmp/recompiled_fixed_login.cgi"


def run_program(path, query, cookie=None):
    env = os.environ.copy()
    env["QUERY_STRING"] = query
    if cookie is None:
        env.pop("HTTP_COOKIE", None)
    else:
        env["HTTP_COOKIE"] = cookie

    result = subprocess.run(
        [path],
        env=env,
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode} for QUERY_STRING={query!r}. "
        f"stderr: {result.stderr}"
    )
    return result


def assert_elf_executable(path):
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"Expected a regular file: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        header = f.read(20)
    assert len(header) >= 18 and header[:4] == b"\x7fELF", (
        f"Expected a compiled ELF executable, not a script or arbitrary file: {path}"
    )
    byte_order = "little" if header[5] == 1 else "big" if header[5] == 2 else None
    assert byte_order is not None, f"Invalid ELF byte order in {path}"
    elf_type = int.from_bytes(header[16:18], byte_order)
    assert elf_type in (2, 3), f"ELF file is not an executable or PIE: {path}"


def compile_submitted_source():
    if os.path.exists(RECOMPILED_PATH):
        os.remove(RECOMPILED_PATH)
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", FIXED_SOURCE_PATH, "-o", RECOMPILED_PATH],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        "fixed_login.c could not be compiled with standard gcc.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_elf_executable(RECOMPILED_PATH)


def test_report_contents():
    """Verify that report.txt contains exactly the malicious URL and CWE ID."""
    assert os.path.isfile(REPORT_PATH), f"Report file missing: {REPORT_PATH}"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.read().splitlines()]

    assert len(lines) >= 2, f"Report file {REPORT_PATH} must contain at least 2 lines."

    expected_url = "http://malicious-tracker.com/steal"
    expected_cwe = "CWE-601"

    assert lines[0] == expected_url, f"Line 1 of report.txt is incorrect. Expected '{expected_url}', got '{lines[0]}'"
    assert lines[1] == expected_cwe, f"Line 2 of report.txt is incorrect. Expected '{expected_cwe}', got '{lines[1]}'"
    assert len(lines) == 2, f"Report file {REPORT_PATH} must contain exactly 2 lines."


def test_fixed_source_exists_and_compiles_as_c():
    """Require the requested C source and independently compile it with gcc."""
    assert os.path.lexists(FIXED_SOURCE_PATH), f"Fixed source missing: {FIXED_SOURCE_PATH}"
    assert stat.S_ISREG(os.lstat(FIXED_SOURCE_PATH).st_mode), (
        f"Fixed source must be a regular C source file: {FIXED_SOURCE_PATH}"
    )
    compile_submitted_source()


def test_fixed_cgi_exists_and_executable():
    """Verify that fixed_login.cgi is a compiled executable."""
    assert os.path.isfile(FIXED_CGI_PATH), f"Compiled fixed binary missing: {FIXED_CGI_PATH}"
    assert os.access(FIXED_CGI_PATH, os.X_OK), f"Compiled fixed binary is not executable: {FIXED_CGI_PATH}"
    assert_elf_executable(FIXED_CGI_PATH)


def test_fixed_cgi_open_redirect_prevention():
    """Retain the original fixed redirect checks."""
    test_cases = [
        ("next=http://evil.com", "Location: /index.html"),
        ("next=//evil.com", "Location: /index.html"),
        ("next=/dashboard/main", "Location: /dashboard/main"),
        ("next=somethingelse", "Location: /index.html")
    ]

    for query_string, expected_location in test_cases:
        result = run_program(FIXED_CGI_PATH, query_string)
        output = result.stdout
        assert expected_location in output, (
            f"Failed open redirect test for QUERY_STRING='{query_string}'. "
            f"Expected to find '{expected_location}' in output, but got:\n{output}"
        )


def test_fixed_cgi_cookie_redaction():
    """Retain the original cookie-redaction assertions."""
    if os.path.exists(AUDIT_LOG_PATH):
        os.remove(AUDIT_LOG_PATH)

    run_program(
        FIXED_CGI_PATH,
        "next=/home",
        "Tracking=999; SessionID=SuperSecret123; Prefs=dark",
    )

    assert os.path.isfile(AUDIT_LOG_PATH), f"Audit log was not created at {AUDIT_LOG_PATH}"

    with open(AUDIT_LOG_PATH, "r", encoding="utf-8") as f:
        log_content = f.read()

    assert "SuperSecret123" not in log_content, "Sensitive SessionID value 'SuperSecret123' was leaked in audit.log!"
    assert "SessionID=REDACTED" in log_content, "SessionID was not properly replaced with 'REDACTED' in audit.log."
    assert "Tracking=999" in log_content, "Other cookie 'Tracking=999' was incorrectly modified or removed."
    assert "Prefs=dark" in log_content, "Other cookie 'Prefs=dark' was incorrectly modified or removed."


def test_dynamic_redirect_validation_for_binary_and_source():
    """Exercise unpredictable safe and unsafe redirects against both artifacts."""
    compile_submitted_source()
    alphabet = string.ascii_letters + string.digits

    safe_paths = []
    unsafe_values = ["", "//" + secrets.token_hex(9), "http://" + secrets.token_hex(8) + ".invalid"]
    for _ in range(8):
        token = "".join(secrets.choice(alphabet) for _ in range(18))
        safe_paths.append("/area/" + token)
        unsafe_values.extend([token, "https://" + token + ".invalid/x", "//" + token + ".invalid/x"])

    cases = [("next=" + path, path) for path in safe_paths]
    cases += [("next=" + value, "/index.html") for value in unsafe_values]
    cases += [
        ("", "/index.html"),
        ("other=/" + secrets.token_hex(8), "/index.html"),
        ("xnext=/" + secrets.token_hex(8), "/index.html"),
    ]

    for executable in (FIXED_CGI_PATH, RECOMPILED_PATH):
        for query, expected in cases:
            result = run_program(executable, query)
            assert result.stdout == f"Location: {expected}\n\n", (
                f"Incorrect CGI output from {executable} for QUERY_STRING={query!r}. "
                f"Expected exact Location header for {expected!r}, got {result.stdout!r}"
            )


def test_dynamic_cookie_redaction_for_binary_and_source():
    """Use unpredictable secrets and verify exact preservation of all other cookie text."""
    compile_submitted_source()
    for executable in (FIXED_CGI_PATH, RECOMPILED_PATH):
        for position in ("start", "middle", "end"):
            secret = "Secret_" + secrets.token_hex(16)
            left_value = secrets.token_hex(7)
            right_value = secrets.token_hex(7)

            if position == "start":
                cookie = f"SessionID={secret}; Tracking={left_value}; Prefs={right_value}"
                expected_cookie = f"SessionID=REDACTED; Tracking={left_value}; Prefs={right_value}"
            elif position == "middle":
                cookie = f"Tracking={left_value}; SessionID={secret}; Prefs={right_value}"
                expected_cookie = f"Tracking={left_value}; SessionID=REDACTED; Prefs={right_value}"
            else:
                cookie = f"Tracking={left_value}; NotSessionID=keep_{right_value}; SessionID={secret}"
                expected_cookie = f"Tracking={left_value}; NotSessionID=keep_{right_value}; SessionID=REDACTED"

            if os.path.exists(AUDIT_LOG_PATH):
                os.remove(AUDIT_LOG_PATH)
            result = run_program(executable, "next=/audit/" + secrets.token_hex(5), cookie)
            assert result.returncode == 0
            assert os.path.isfile(AUDIT_LOG_PATH), f"Audit log was not created by {executable}"
            with open(AUDIT_LOG_PATH, "r", encoding="utf-8") as f:
                log_content = f.read()

            assert secret not in log_content, f"Session secret leaked by {executable}"
            assert log_content == f"Login attempt. Cookie: {expected_cookie}\n", (
                f"{executable} did not redact only the SessionID value while preserving "
                f"the audit-log structure and other cookies. Got {log_content!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
