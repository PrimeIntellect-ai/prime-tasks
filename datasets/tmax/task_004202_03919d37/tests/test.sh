#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import shlex
import stat
import subprocess
import tempfile
from zoneinfo import ZoneInfo

DEPLOY = "/home/user/deploy.sh"
SOURCE = "/home/user/monitor.cpp"
BINARY = "/home/user/monitor_bin"
UNIT = "/home/user/.config/systemd/user/app-monitor.service"
SPOOL = "/home/user/alerts/mail_spool"


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY), f"{DEPLOY} does not exist."
    assert os.access(DEPLOY, os.X_OK), f"{DEPLOY} is not executable."


def test_deploy_script_runs_successfully_and_compiles_source():
    # Replace any pre-existing monitor with a marker, then instrument g++ so the
    # deployment must invoke it with the required source and destination.
    os.makedirs(os.path.dirname(BINARY), exist_ok=True)
    with open(BINARY, "wb") as f:
        f.write(b"#!/bin/sh\necho verifier-marker\n")
    os.chmod(BINARY, 0o755)

    real_gpp = "/usr/bin/g++.verifier-real"
    gpp = "/usr/bin/g++"
    assert os.path.exists(gpp), "g++ is unavailable"
    assert not os.path.lexists(real_gpp), f"Unexpected existing path: {real_gpp}"

    fd, call_log = tempfile.mkstemp(prefix="gpp_calls_")
    os.close(fd)
    os.rename(gpp, real_gpp)
    try:
        wrapper = f'''#!/bin/sh
{{
  printf 'CALL'
  for arg in "$@"; do printf '\\t%s' "$arg"; done
  printf '\\n'
}} >> {shlex.quote(call_log)}
exec {shlex.quote(real_gpp)} "$@"
'''
        with open(gpp, "w") as f:
            f.write(wrapper)
        os.chmod(gpp, 0o755)

        result1 = subprocess.run([DEPLOY], capture_output=True, timeout=60)
        assert result1.returncode == 0, (
            f"{DEPLOY} failed on first run: {result1.stderr.decode(errors='replace')}"
        )

        result2 = subprocess.run([DEPLOY], capture_output=True, timeout=60)
        assert result2.returncode == 0, (
            f"{DEPLOY} failed on second run (not idempotent): "
            f"{result2.stderr.decode(errors='replace')}"
        )
    finally:
        if os.path.lexists(gpp):
            os.remove(gpp)
        os.rename(real_gpp, gpp)

    with open(call_log, "r", errors="replace") as f:
        calls = [line.rstrip("\n").split("\t")[1:] for line in f if line.startswith("CALL")]
    os.remove(call_log)

    def is_required_compile(args):
        if SOURCE not in args:
            return False
        if f"-o{BINARY}" in args:
            return True
        return any(args[i] == "-o" and i + 1 < len(args) and args[i + 1] == BINARY
                   for i in range(len(args)))

    assert any(is_required_compile(args) for args in calls), (
        f"{DEPLOY} did not compile {SOURCE} with g++ into {BINARY}"
    )
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"{BINARY} was not compiled."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    # Independently ensure the submitted C++ source is compilable.
    with tempfile.TemporaryDirectory() as td:
        check_bin = os.path.join(td, "monitor_from_source")
        compiled = subprocess.run(
            [gpp, SOURCE, "-o", check_bin], capture_output=True, timeout=60
        )
        assert compiled.returncode == 0, (
            f"{SOURCE} does not compile with g++: "
            f"{compiled.stderr.decode(errors='replace')}"
        )


def test_mail_spool_permissions():
    assert os.path.isdir(SPOOL), f"{SPOOL} directory does not exist."
    perms = stat.S_IMODE(os.stat(SPOOL).st_mode)
    assert perms == 0o700, f"{SPOOL} permissions are {oct(perms)}, expected 0o700."


def parse_unit_sections(content):
    sections = {}
    current = None
    for lineno, raw in enumerate(content.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            sections.setdefault(current, [])
            continue
        assert current is not None, f"Directive outside a section on line {lineno}"
        assert "=" in line, f"Malformed unit directive on line {lineno}: {raw!r}"
        key, value = line.split("=", 1)
        sections[current].append((key.strip(), value.strip()))
    return sections


def test_systemd_unit_file():
    assert os.path.isfile(UNIT), f"{UNIT} does not exist."
    with open(UNIT, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "Restart=always" in content, "Missing 'Restart=always' in unit file."
    assert "RestartSec=3" in content, "Missing 'RestartSec=3' in unit file."
    assert "TZ=Asia/Tokyo" in content, "Missing TZ=Asia/Tokyo environment variable in unit file."
    required_exec = "ExecStart=/home/user/monitor_bin /home/user/app.log /home/user/alerts/mail_spool/alerts.eml"
    assert required_exec in content, "ExecStart line does not match the required format."

    # Require systemd itself to accept the unit.
    verified = subprocess.run(
        ["systemd-analyze", "verify", UNIT], capture_output=True, timeout=30
    )
    assert verified.returncode == 0, (
        "systemd rejected app-monitor.service: "
        + verified.stderr.decode(errors="replace")
    )

    sections = parse_unit_sections(content)
    assert "Service" in sections, "Missing [Service] section."
    service = sections["Service"]

    def values(key):
        return [value for found_key, value in service if found_key == key]

    assert values("ExecStart") == [
        "/home/user/monitor_bin /home/user/app.log /home/user/alerts/mail_spool/alerts.eml"
    ], "ExecStart must appear exactly once in [Service] with the required command."
    assert values("Restart") == ["always"], "Restart=always must appear exactly once in [Service]."
    assert len(values("RestartSec")) == 1 and values("RestartSec")[0] in {
        "3", "3s", "3sec", "3seconds"
    }, "RestartSec in [Service] must specify exactly 3 seconds."

    environment_tokens = []
    for value in values("Environment"):
        environment_tokens.extend(shlex.split(value))
    assert environment_tokens.count("TZ=Asia/Tokyo") == 1, (
        "[Service] must configure Environment=TZ=Asia/Tokyo exactly once."
    )


def make_log(match_count):
    nonce = secrets.token_hex(12)
    lines = [
        f"INFO {nonce} system starting",
        f"REJECT  key_auth {nonce}",
        f"reject key_auth {nonce}",
        f"REJECT key_authX {nonce}",
        f"REJECT key-aut {nonce}",
        f"DEBUG {nonce} connecting",
    ]
    for i in range(match_count):
        # These all contain the exact required string, but are not fixed lines.
        lines.append(f"{secrets.token_hex(5)} REJECT key_auth event={i}-{nonce}")
    secrets.SystemRandom().shuffle(lines)
    return "\n".join(lines) + "\n"


SNIPPET_RE = re.compile(
    r"To: admin@localhost\n"
    r"Subject: Alert - Auth Rejected\n"
    r"Date: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\n"
    r"\n"
    r"Auth failure detected\.\n?"
)


def assert_exact_snippets(text, expected_count, earliest, latest):
    position = 0
    dates = []
    while position < len(text):
        match = SNIPPET_RE.match(text, position)
        assert match is not None, f"Malformed or extra output at byte {position}: {text[position:]!r}"
        dates.append(datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S"))
        position = match.end()
    assert len(dates) == expected_count, (
        f"Expected exactly {expected_count} snippets, found {len(dates)}."
    )
    lower = earliest.replace(tzinfo=None) - datetime.timedelta(seconds=2)
    upper = latest.replace(tzinfo=None) + datetime.timedelta(seconds=2)
    for value in dates:
        assert lower <= value <= upper, (
            f"Date {value} is not the current Asia/Tokyo local time "
            f"(expected between {lower} and {upper})."
        )


def test_monitor_bin_logic_with_runtime_generated_inputs_and_append_semantics():
    assert os.path.isfile(BINARY), f"{BINARY} was not compiled."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."

    tokyo = ZoneInfo("Asia/Tokyo")
    env = os.environ.copy()
    env["TZ"] = "Asia/Tokyo"
    counts = [0, 1 + secrets.randbelow(5), 2 + secrets.randbelow(6), secrets.randbelow(7)]
    secrets.SystemRandom().shuffle(counts)

    with tempfile.TemporaryDirectory() as td:
        out_path = os.path.join(td, "alerts.eml")
        prefix = "pre-existing-alert-data-" + secrets.token_hex(10) + "\n"
        with open(out_path, "w") as f:
            f.write(prefix)

        for run_number, expected_count in enumerate(counts):
            log_path = os.path.join(td, f"input-{run_number}-{secrets.token_hex(5)}.log")
            with open(log_path, "w") as f:
                f.write(make_log(expected_count))

            with open(out_path, "r") as f:
                before_content = f.read()
            earliest = datetime.datetime.now(tokyo)
            result = subprocess.run(
                [BINARY, log_path, out_path], env=env, capture_output=True, timeout=20
            )
            latest = datetime.datetime.now(tokyo)
            assert result.returncode == 0, (
                f"{BINARY} failed to execute: {result.stderr.decode(errors='replace')}"
            )
            assert os.path.isfile(out_path), "Output alert file was not created."

            with open(out_path, "r") as f:
                after_content = f.read()
            assert after_content.startswith(before_content), (
                "The monitor truncated or modified existing alert-file content instead of appending."
            )
            added = after_content[len(before_content):]
            assert_exact_snippets(added, expected_count, earliest, latest)

        with open(out_path, "r") as f:
            final_content = f.read()
        assert final_content.startswith(prefix), "Pre-existing output content was not preserved."

        # Preserve the original first-snippet checks as well.
        if sum(counts) > 0:
            generated = final_content[len(prefix):]
            assert "To: admin@localhost" in generated, "Missing 'To: admin@localhost'"
            assert "Subject: Alert - Auth Rejected" in generated, (
                "Missing 'Subject: Alert - Auth Rejected'"
            )
            date_match = re.search(
                r"Date: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", generated
            )
            assert date_match is not None, "Date format is incorrect or missing."
            assert generated.count("Auth failure detected.") == sum(counts), (
                "The number of generated messages does not match the input."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
