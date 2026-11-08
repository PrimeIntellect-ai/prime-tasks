#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import uuid


def test_bash_profile_configured():
    path = "/home/user/.bash_profile"
    assert os.path.isfile(path), f"File {path} does not exist. You must create or modify it."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original PATH assertion.
    assert re.search(r"export\s+PATH=.*/home/user/custom_bin", content), \
        f"{path} does not properly export PATH with /home/user/custom_bin"

    # Preserve the original MONITOR_LOG_DIR assertion.
    assert re.search(r"export\s+MONITOR_LOG_DIR=/home/user/logs", content), \
        f"{path} does not properly export MONITOR_LOG_DIR=/home/user/logs"


def test_logs_directory_exists():
    path = "/home/user/logs"
    assert os.path.isdir(path), f"Directory {path} does not exist. You must create it."


def test_monitor_script_modifications():
    path = "/home/user/monitor.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert stat.S_ISREG(os.stat(path).st_mode), f"{path} is not a regular file."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert re.search(r"(source|\.)\s+/home/user/\.bash_profile", content), \
        f"{path} does not source /home/user/.bash_profile"

    # Preserve the original text-processing assertion.
    assert re.search(r"(awk|sed|grep)", content), \
        f"{path} does not appear to use awk, sed, or grep to filter the configuration file."

    # The required tool must occur in executable code rather than only in comments.
    non_comment_code = "\n".join(
        line for line in content.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"(^|[^A-Za-z0-9_])(awk|sed|grep)([^A-Za-z0-9_]|$)", non_comment_code), \
        f"{path} only mentions awk, sed, or grep in comments."


def test_uptime_report_content():
    path = "/home/user/uptime_report.log"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the script?"

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "AuthService | 500 | 200 | DOWN",
        "Database | 200 | 200 | UP",
        "Cache | 200 | 200 | UP",
        "UnknownService | 404 | 200 | DOWN"
    ]

    assert len(lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in {path}, found {len(lines)}."

    for expected, actual in zip(expected_lines, lines):
        assert actual == expected, \
            f"Mismatch in {path}. Expected: '{expected}', Got: '{actual}'"


def test_monitor_behavior_under_empty_environment():
    profile = "/home/user/.bash_profile"
    config = "/home/user/services.conf"
    mock = "/home/user/custom_bin/mock_curl"
    report = "/home/user/uptime_report.log"

    token = uuid.uuid4().hex
    marker = f"/tmp/profile_sourced_{token}"
    calls = f"/tmp/mock_calls_{token}"

    names = [f"Alpha{token[:8]}", f"Beta{token[8:16]}", f"Gamma{token[16:24]}"]
    endpoints = [f"http://dynamic-{token}/one", f"http://dynamic-{token}/two", f"http://dynamic-{token}/three"]
    actual_codes = ["201", "418", "503"]
    expected_codes = ["201", "200", "503"]

    expected_report = [
        f"{names[0]} | 201 | 201 | UP",
        f"{names[1]} | 418 | 200 | DOWN",
        f"{names[2]} | 503 | 503 | UP",
    ]

    original = {}
    for path in (profile, config, mock, report):
        if os.path.exists(path):
            with open(path, "rb") as f:
                original[path] = f.read()
        else:
            original[path] = None
    mock_mode = os.stat(mock).st_mode

    try:
        # A marker added to the real profile proves that monitor.sh actually sources it.
        with open(profile, "ab") as f:
            f.write(f"\n: > {marker}\n".encode())

        with open(config, "w") as f:
            f.write(f"# TrapService http://must-not-be-called-{token} 200\n")
            f.write("\n")
            f.write(f"{names[0]} {endpoints[0]} {expected_codes[0]}\n")
            f.write("\n")
            f.write(f"# Another ignored comment {token}\n")
            f.write(f"{names[1]} {endpoints[1]} {expected_codes[1]}\n")
            f.write(f"{names[2]} {endpoints[2]} {expected_codes[2]}\n")

        with open(mock, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\n' \"$1\" >> {calls}\n")
            f.write("case \"$1\" in\n")
            for endpoint, code in zip(endpoints, actual_codes):
                f.write(f"  {endpoint}) printf '%s\\n' {code} ;;\n")
            f.write("  *) printf '%s\\n' 599 ;;\n")
            f.write("esac\n")
        os.chmod(mock, 0o755)

        if os.path.exists(report):
            os.unlink(report)
        if os.path.exists(marker):
            os.unlink(marker)
        if os.path.exists(calls):
            os.unlink(calls)

        result = subprocess.run(
            ["/usr/bin/env", "-i", "/bin/bash", "/home/user/monitor.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, \
            f"monitor.sh failed under env -i: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.isfile(marker), \
            "monitor.sh did not actually source /home/user/.bash_profile during execution."
        assert os.path.isfile(report), "monitor.sh did not create /home/user/uptime_report.log."

        with open(report, "r") as f:
            actual_report = [line.rstrip("\n") for line in f if line.strip()]
        assert actual_report == expected_report, \
            f"Dynamic monitoring output was incorrect. Expected {expected_report!r}, got {actual_report!r}."

        assert os.path.isfile(calls), "The dynamically installed mock_curl was never called."
        with open(calls, "r") as f:
            actual_calls = [line.rstrip("\n") for line in f]
        assert actual_calls == endpoints, \
            f"mock_curl must be called once for each valid entry and never for comments/blanks; got {actual_calls!r}."
    finally:
        for path, data in original.items():
            if data is None:
                if os.path.exists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
        if os.path.exists(mock):
            os.chmod(mock, stat.S_IMODE(mock_mode))
        for path in (marker, calls):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
