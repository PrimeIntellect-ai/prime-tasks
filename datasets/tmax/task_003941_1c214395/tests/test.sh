#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import datetime
import os
import re
import secrets
import shlex
import stat
import subprocess
import tempfile
from zoneinfo import ZoneInfo

LOG_FILE = "/home/user/network_logs/status.log"
SCRIPT_FILE = "/home/user/scripts/monitor.py"
NETCHECK_FILE = "/home/user/bin/netcheck"


def test_final_state_and_behavior():
    # Preserve the original final-state assertions.
    assert os.path.isfile(LOG_FILE), f"The log file {LOG_FILE} does not exist. Did you run the script?"
    with open(LOG_FILE, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, f"The log file {LOG_FILE} is empty."

    original_pattern = re.compile(
        r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] "
        r"\[America/New_York\] STATUS: OK - Latency 14ms$"
    )
    assert any(original_pattern.match(line.strip()) for line in lines), \
        f"No line in {LOG_FILE} matched the expected format and timezone."

    assert os.path.isfile(SCRIPT_FILE), f"The script {SCRIPT_FILE} is missing."
    with open(SCRIPT_FILE, "r") as f:
        content = f.read()

    assert "/home/user/bin/netcheck" in content, \
        "The script does not use the absolute path to netcheck."
    assert "/home/user/network_logs/status.log" in content, \
        "The script does not use the absolute path for the log file."
    assert "America/New_York" in content, \
        "The script does not reference 'America/New_York'."
    has_zoneinfo = "zoneinfo" in content or "ZoneInfo" in content
    has_pytz = "pytz" in content
    assert has_zoneinfo or has_pytz, \
        "The script must use 'zoneinfo' or 'pytz' for timezone handling."

    # Require a real timezone-library import, rather than a keyword in a comment.
    tree = ast.parse(content, filename=SCRIPT_FILE)
    timezone_imported = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            timezone_imported |= any(
                alias.name == "zoneinfo" or alias.name == "pytz"
                for alias in node.names
            )
        elif isinstance(node, ast.ImportFrom):
            timezone_imported |= node.module in ("zoneinfo", "pytz")
    assert timezone_imported, "The script must actually import zoneinfo or pytz."

    # Exercise the submitted script with an unpredictable netcheck result. The
    # marker proves the absolute executable was run, rather than its output being
    # guessed or copied from a prewritten log line.
    token = "VERIFY-" + secrets.token_hex(16)
    marker = "/tmp/netcheck-invoked-" + secrets.token_hex(12)
    with open(NETCHECK_FILE, "rb") as f:
        original_netcheck = f.read()
    original_mode = stat.S_IMODE(os.stat(NETCHECK_FILE).st_mode)
    with open(LOG_FILE, "rb") as f:
        old_log = f.read()

    replacement = (
        "#!/bin/sh\n"
        f"printf '%s\\n' invoked > {shlex.quote(marker)}\n"
        f"printf '%s\\n' {shlex.quote(token)}\n"
    ).encode()

    try:
        with open(NETCHECK_FILE, "wb") as f:
            f.write(replacement)
        os.chmod(NETCHECK_FILE, 0o755)

        with tempfile.TemporaryDirectory() as cwd:
            relative_log = os.path.join(cwd, "status.log")
            env = os.environ.copy()
            env["PATH"] = "/usr/bin:/bin"
            env["TZ"] = "UTC"

            before = datetime.datetime.now(datetime.timezone.utc)
            result = subprocess.run(
                ["/usr/bin/python3", SCRIPT_FILE],
                cwd=cwd,
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            after = datetime.datetime.now(datetime.timezone.utc)

            assert result.returncode == 0, (
                f"monitor.py failed when run from a cron-like environment: "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert os.path.isfile(marker), \
                "monitor.py did not execute /home/user/bin/netcheck."
            assert not os.path.exists(relative_log), \
                "monitor.py wrote status.log relative to its current working directory."

        with open(LOG_FILE, "rb") as f:
            new_log = f.read()
        assert new_log.startswith(old_log), \
            "monitor.py did not append to the existing absolute log file."
        appended = new_log[len(old_log):].decode("utf-8")

        dynamic_pattern = re.compile(
            r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] "
            r"\[America/New_York\] STATUS: " + re.escape(token) + r"\n$"
        )
        match = dynamic_pattern.fullmatch(appended)
        assert match, (
            "A single execution must append exactly one correctly formatted line "
            "containing the actual netcheck output."
        )

        # Derive acceptable New York timestamps from the verifier's own clock.
        # A small margin handles second boundaries around process startup/exit.
        cursor = (before - datetime.timedelta(seconds=2)).replace(microsecond=0)
        end = (after + datetime.timedelta(seconds=2)).replace(microsecond=0)
        allowed = set()
        ny = ZoneInfo("America/New_York")
        while cursor <= end:
            allowed.add(cursor.astimezone(ny).strftime("%Y-%m-%d %H:%M:%S"))
            cursor += datetime.timedelta(seconds=1)
        assert match.group(1) in allowed, \
            "The logged timestamp is not the actual current time in America/New_York."
    finally:
        with open(NETCHECK_FILE, "wb") as f:
            f.write(original_netcheck)
        os.chmod(NETCHECK_FILE, original_mode)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
