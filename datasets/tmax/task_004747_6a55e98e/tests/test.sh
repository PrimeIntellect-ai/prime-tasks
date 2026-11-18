#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import shutil
import stat
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

APP = Path("/home/user/app")
PARSER = APP / "bin/parser"
RAW = APP / "data/raw.dat"
FIXED = APP / "data/fixed.dat"
EXPECTED_JSON = b'{"status": "success", "payload": "error99"}\n'
EXPECTED_FIXED = struct.pack("<II", 0xDEADC0DE, 7) + b"error99"
EXPECTED_RAW = struct.pack("<II", 0xDEADC0DE, 14) + "error99".encode("utf-16le")


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **kwargs)


def test_parser_is_compiled_and_behaves_correctly():
    assert APP.is_dir(), f"Directory {APP} does not exist."
    assert PARSER.is_file(), f"Parser {PARSER} is missing."
    assert os.access(PARSER, os.X_OK), "Parser is not executable."
    assert PARSER.read_bytes().startswith(b"\x7fELF"), "Parser must remain a compiled ELF binary."

    for payload in (b"probe17", b"dynamic42"):
        with tempfile.NamedTemporaryFile() as sample:
            sample.write(struct.pack("<II", 0xDEADC0DE, len(payload)) + payload)
            sample.flush()
            result = run([str(PARSER), sample.name])
        expected = '{"status": "success", "payload": "%s"}\n' % payload.decode("ascii")
        assert result.returncode == 0, result.stderr
        assert result.stdout == expected

    with tempfile.NamedTemporaryFile() as bad:
        bad.write(struct.pack("<II", 0x12345678, 3) + b"bad")
        bad.flush()
        result = run([str(PARSER), bad.name])
    assert result.returncode != 0


def test_resolution_json_exists_and_valid():
    res_path = APP / "resolution.json"
    assert res_path.is_file(), f"File {res_path} is missing."
    try:
        data = json.loads(res_path.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f"{res_path} is not valid JSON: {exc}")

    assert isinstance(data, dict), "resolution.json should contain a JSON object."
    assert set(data) == {"magic_hex", "original_encoding"}, \
        "resolution.json must contain exactly magic_hex and original_encoding."
    assert isinstance(data["magic_hex"], str)
    assert data["magic_hex"] == "deadc0de", \
        "magic_hex must be the lowercase 4-byte header value without a prefix."
    assert isinstance(data["original_encoding"], str)
    encoding = data["original_encoding"].lower().replace("-", "").replace("_", "").replace(" ", "")
    assert encoding == "utf16le", \
        f"Expected original_encoding to identify UTF-16LE, got {data['original_encoding']!r}."


def test_makefile_updated():
    makefile = APP / "Makefile"
    assert makefile.is_file(), f"File {makefile} is missing."
    content = makefile.read_text()
    assert "data/fixed.dat" in content, "Makefile does not reference data/fixed.dat."
    assert "data/raw.dat" not in content, "Makefile should no longer reference data/raw.dat."


def test_raw_and_fixed_binary_formats():
    assert RAW.is_file(), f"File {RAW} is missing."
    assert RAW.read_bytes() == EXPECTED_RAW, "raw.dat no longer contains the supplied malformed record."
    assert FIXED.is_file(), f"File {FIXED} is missing."
    assert FIXED.read_bytes() == EXPECTED_FIXED, \
        "fixed.dat must contain the original magic, a 7-byte length, and the UTF-8 payload with no trailing data."

    result = run([str(PARSER), str(FIXED)])
    assert result.returncode == 0, result.stderr
    assert result.stdout.encode() == EXPECTED_JSON


def test_conversion_script_recreates_fixed_dat():
    excluded = {
        PARSER.resolve(), RAW.resolve(), FIXED.resolve(),
        (APP / "Makefile").resolve(), (APP / "expected.json").resolve(),
        (APP / "actual.json").resolve(), (APP / "resolution.json").resolve(),
    }
    candidates = []
    for path in APP.rglob("*"):
        if not path.is_file() or path.resolve() in excluded:
            continue
        mode = path.stat().st_mode
        if path.suffix.lower() in {".py", ".sh", ".bash"} or mode & stat.S_IXUSR:
            candidates.append(path)

    assert candidates, "No conversion script was created."
    original_fixed = FIXED.read_bytes()
    succeeded = None
    try:
        for candidate in candidates:
            commands = []
            suffix = candidate.suffix.lower()
            if suffix == ".py":
                base = ["python3", str(candidate)]
            elif suffix in {".sh", ".bash"}:
                base = ["bash", str(candidate)]
            elif os.access(candidate, os.X_OK):
                base = [str(candidate)]
            else:
                continue
            commands.extend([base, base + [str(RAW), str(FIXED)]])

            for command in commands:
                FIXED.unlink(missing_ok=True)
                try:
                    result = run(command, cwd=str(APP), timeout=10)
                except (subprocess.TimeoutExpired, OSError):
                    continue
                if result.returncode == 0 and FIXED.is_file() and FIXED.read_bytes() == EXPECTED_FIXED:
                    succeeded = candidate
                    break
            if succeeded is not None:
                break
    finally:
        if not FIXED.is_file() or FIXED.read_bytes() != EXPECTED_FIXED:
            FIXED.write_bytes(original_fixed)

    assert succeeded is not None, \
        "No submitted script successfully converted raw.dat into the required fixed.dat."


def test_make_test_really_runs_parser_and_checks_output():
    assert (APP / "expected.json").read_bytes() == EXPECTED_JSON, "expected.json was modified."
    assert FIXED.read_bytes() == EXPECTED_FIXED

    fd, saved_name = tempfile.mkstemp(prefix="original-parser-")
    os.close(fd)
    saved = Path(saved_name)
    log = Path(tempfile.mktemp(prefix="parser-invocations-"))
    shutil.copy2(PARSER, saved)

    wrapper = f'''#!/bin/sh
echo "$@" >> {shlex.quote(str(log))}
case "$VERIFIER_PARSER_MODE" in
  fail) exit 73 ;;
  wrong) printf '%s\\n' '{{"status": "success", "payload": "wrong"}}'; exit 0 ;;
esac
exec {shlex.quote(str(saved))} "$@"
'''

    try:
        PARSER.write_text(wrapper)
        PARSER.chmod(0o755)

        for mode in ("fail", "wrong"):
            (APP / "actual.json").unlink(missing_ok=True)
            env = os.environ.copy()
            env["VERIFIER_PARSER_MODE"] = mode
            result = run(["make", "-B", "test"], cwd=str(APP), env=env)
            assert result.returncode != 0, \
                f"make test succeeded when the parser was forced into {mode!r} mode."

        (APP / "actual.json").unlink(missing_ok=True)
        env = os.environ.copy()
        env["VERIFIER_PARSER_MODE"] = "pass"
        result = run(["make", "-B", "test"], cwd=str(APP), env=env)
        assert result.returncode == 0, \
            f"'make test' failed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert (APP / "actual.json").is_file(), "make test did not produce actual.json."
        assert (APP / "actual.json").read_bytes() == EXPECTED_JSON

        invocations = log.read_text().splitlines() if log.exists() else []
        used_fixed = False
        for line in invocations:
            for arg in shlex.split(line):
                resolved = Path(arg) if os.path.isabs(arg) else APP / arg
                if resolved.resolve() == FIXED.resolve():
                    used_fixed = True
        assert used_fixed, "make test did not invoke the parser on data/fixed.dat."
    finally:
        shutil.copy2(saved, PARSER)
        PARSER.chmod(0o755)
        saved.unlink(missing_ok=True)
        log.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
