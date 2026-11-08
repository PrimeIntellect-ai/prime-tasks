#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import locale
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
from zoneinfo import ZoneInfo


def uncomment_c(source):
    """Remove C comments and obscure nonempty literals while preserving empty strings."""
    out = []
    i = 0
    state = "code"
    quote = None
    literal = []
    while i < len(source):
        if state == "code":
            if source.startswith("//", i):
                state = "line_comment"
                i += 2
            elif source.startswith("/*", i):
                state = "block_comment"
                i += 2
            elif source[i] in ('\"', "'"):
                quote = source[i]
                literal = []
                state = "literal"
                i += 1
            else:
                out.append(source[i])
                i += 1
        elif state == "line_comment":
            if source[i] == "\n":
                out.append("\n")
                state = "code"
            i += 1
        elif state == "block_comment":
            if source.startswith("*/", i):
                state = "code"
                i += 2
            else:
                if source[i] == "\n":
                    out.append("\n")
                i += 1
        else:
            if source[i] == "\\" and i + 1 < len(source):
                literal.extend(source[i:i + 2])
                i += 2
            elif source[i] == quote:
                if quote == '\"':
                    out.append('\"\"' if not literal else '\"STR\"')
                else:
                    out.append("'X'")
                state = "code"
                i += 1
            else:
                literal.append(source[i])
                i += 1
    return "".join(out)


def run_daemon(path):
    env = os.environ.copy()
    env["TZ"] = "Asia/Tokyo"
    env["LC_ALL"] = "ja_JP.UTF-8"
    before = int(time.time())
    result = subprocess.run([path], env=env, text=True, capture_output=True, timeout=8)
    after = int(time.time())
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert len(lines) == 5, f"daemon produced {len(lines)} lines instead of 5"
    stamps = []
    for line in lines:
        match = re.fullmatch(r"\[(.*)\] Heartbeat event", line)
        assert match, f"unexpected daemon output: {line!r}"
        stamps.append(match.group(1))

    old_locale = locale.setlocale(locale.LC_ALL)
    try:
        for name in ("ja_JP.UTF-8", "ja_JP.utf8"):
            try:
                locale.setlocale(locale.LC_ALL, name)
                break
            except locale.Error:
                pass
        else:
            raise AssertionError("Japanese locale is unavailable")
        expected = {
            datetime.datetime.fromtimestamp(ts, ZoneInfo("Asia/Tokyo")).strftime("%c")
            for ts in range(before - 1, after + 2)
        }
    finally:
        locale.setlocale(locale.LC_ALL, old_locale)
    assert all(stamp in expected for stamp in stamps), (
        "daemon timestamps do not use the Japanese locale and Asia/Tokyo timezone"
    )


def test_c_code_fixed_and_deployed_binary():
    file_path = "/home/user/daemon.c"
    assert os.path.isfile(file_path), f"{file_path} does not exist."
    with open(file_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "setlocale" in content, "daemon.c does not contain 'setlocale'."
    assert "tzset" in content, "daemon.c does not contain 'tzset'."

    code = uncomment_c(content)
    assert re.search(r"\bsetlocale\s*\(\s*LC_ALL\s*,\s*\"\"\s*\)", code), (
        "daemon.c must actively call setlocale(LC_ALL, \"\")"
    )
    assert re.search(r"\btzset\s*\(\s*\)", code), "daemon.c must actively call tzset()"

    binary_path = "/home/user/daemon"
    assert os.path.isfile(binary_path), f"{binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "daemon is not a compiled ELF program"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "daemon")
        compiled = subprocess.run(
            ["gcc", "-O0", file_path, "-o", rebuilt], text=True, capture_output=True
        )
        assert compiled.returncode == 0, f"daemon.c does not compile:\n{compiled.stderr}"
        symbols = subprocess.run(
            ["nm", "-D", rebuilt], text=True, capture_output=True, check=True
        ).stdout
        assert re.search(r"\bU\s+setlocale(?:@|$)", symbols, re.MULTILINE)
        assert re.search(r"\bU\s+tzset(?:@|$)", symbols, re.MULTILINE)
        run_daemon(rebuilt)

    run_daemon(binary_path)


def test_launch_script():
    script_path = "/home/user/start.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."
    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "TZ=Asia/Tokyo" in content, "start.sh does not set TZ=Asia/Tokyo."
    assert "LC_ALL=ja_JP.UTF-8" in content, "start.sh does not set LC_ALL=ja_JP.UTF-8."
    assert "/home/user/daemon.log" in content, "start.sh does not redirect to /home/user/daemon.log."
    assert "&" in content, "start.sh does not appear to run the daemon in the background."

    daemon = "/home/user/daemon"
    saved = "/home/user/.daemon.verifier-saved"
    log = "/home/user/daemon.log"
    log_existed = os.path.exists(log)
    old_log = open(log, "rb").read() if log_existed else None
    old_mode = stat.S_IMODE(os.stat(log).st_mode) if log_existed else None
    old_uid = os.stat(log).st_uid if log_existed else None
    old_gid = os.stat(log).st_gid if log_existed else None
    os.replace(daemon, saved)
    try:
        with open(daemon, "w") as f:
            f.write("#!/bin/sh\nprintf 'TZ=%s\\nLC_ALL=%s\\n' \"$TZ\" \"$LC_ALL\"\n")
        os.chmod(daemon, 0o755)
        if os.path.exists(log):
            os.unlink(log)
        started = time.monotonic()
        result = subprocess.run(
            [script_path], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=1
        )
        elapsed = time.monotonic() - started
        assert result.returncode == 0, result.stderr
        assert elapsed < 1, "start.sh did not leave the daemon running in the background"
        for _ in range(20):
            if os.path.exists(log) and os.path.getsize(log) > 0:
                break
            time.sleep(0.05)
        assert os.path.isfile(log), "start.sh did not create /home/user/daemon.log"
        output = open(log).read()
        assert "TZ=Asia/Tokyo" in output, "TZ was not exported to the daemon"
        assert "LC_ALL=ja_JP.UTF-8" in output, "LC_ALL was not exported to the daemon"
        assert result.stdout == "", "daemon stdout was not redirected to daemon.log"
    finally:
        if os.path.exists(daemon):
            os.unlink(daemon)
        os.replace(saved, daemon)
        if log_existed:
            with open(log, "wb") as f:
                f.write(old_log)
            os.chmod(log, old_mode)
            os.chown(log, old_uid, old_gid)
        elif os.path.exists(log):
            os.unlink(log)


def test_logrotate_config():
    config_path = "/home/user/logrotate.conf"
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "/home/user/daemon.log" in content, "logrotate.conf does not target /home/user/daemon.log."
    for directive in ["daily", "rotate 3", "compress", "missingok"]:
        pattern = r"\b" + directive.replace(" ", r"\s+") + r"\b"
        assert re.search(pattern, content), f"logrotate.conf is missing the '{directive}' directive."

    active = re.sub(r"#.*", "", content)
    blocks = re.findall(r"([^{}]+)\{([^{}]*)\}", active, re.DOTALL)
    matching = [(header, body) for header, body in blocks
                if "/home/user/daemon.log" in header.split()]
    assert len(matching) == 1, "daemon.log must be targeted by exactly one active logrotate block"
    header, body = matching[0]
    assert header.split() == ["/home/user/daemon.log"], "logrotate target is malformed"
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    assert "daily" in lines, "daily must be an active directive"
    assert "compress" in lines, "compress must be an active directive"
    assert "missingok" in lines, "missingok must be an active directive"
    rotates = [re.fullmatch(r"rotate\s+(\d+)", line) for line in lines]
    rotates = [m for m in rotates if m]
    assert len(rotates) == 1 and rotates[0].group(1) == "3", "rotate must actively specify exactly 3"
    assert not any(line in {"weekly", "monthly", "yearly", "hourly", "nocompress", "nomissingok"}
                   for line in lines), "logrotate block contains a conflicting directive"

    with tempfile.TemporaryDirectory() as td:
        copied = os.path.join(td, "logrotate.conf")
        shutil.copyfile(config_path, copied)
        os.chmod(td, 0o755)
        os.chmod(copied, 0o644)
        parsed = subprocess.run(
            ["runuser", "-u", "user", "--", "logrotate", "--debug", copied],
            text=True, capture_output=True
        )
        assert parsed.returncode == 0, f"logrotate rejected the configuration:\n{parsed.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
