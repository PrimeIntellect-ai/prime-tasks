#!/bin/bash
set -e
mkdir -p /logs/verifier

HOOK_DIR=/tmp/verifier_hooks
EVENT_LOG=/tmp/parser_sandbox_events.jsonl
rm -rf "$HOOK_DIR"
mkdir -p "$HOOK_DIR"

cat << 'HOOK_EOF' > "$HOOK_DIR/sitecustomize.py"
import json
import os
import re
import resource

_EVENT_LOG = os.environ.get("VERIFIER_EVENT_LOG")


def _record(event, **fields):
    if not _EVENT_LOG:
        return
    data = {"event": event, "pid": os.getpid()}
    data.update(fields)
    line = (json.dumps(data, sort_keys=True) + "\n").encode("utf-8", "replace")
    fd = os.open(_EVENT_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, line)
    finally:
        os.close(fd)


_real_setrlimit = resource.setrlimit


def _setrlimit(which, limits):
    try:
        soft, hard = limits
        _record("setrlimit", which=int(which), soft=soft, hard=hard)
    except Exception:
        _record("setrlimit", which=repr(which), limits=repr(limits))
    return _real_setrlimit(which, limits)


resource.setrlimit = _setrlimit

_real_search = re.search
_real_match = re.match
_real_fullmatch = re.fullmatch
_real_compile = re.compile


def _pattern_text(pattern):
    value = getattr(pattern, "pattern", pattern)
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


def _input_text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


def _log_regex(operation, pattern, value):
    if _pattern_text(pattern) == "(a+)+b":
        _record("regex", operation=operation, pattern="(a+)+b", input=_input_text(value))


def _search(pattern, string, flags=0):
    _log_regex("search", pattern, string)
    return _real_search(pattern, string, flags)


def _match(pattern, string, flags=0):
    _log_regex("match", pattern, string)
    return _real_match(pattern, string, flags)


def _fullmatch(pattern, string, flags=0):
    _log_regex("fullmatch", pattern, string)
    return _real_fullmatch(pattern, string, flags)


class _TrackedPattern:
    def __init__(self, compiled):
        self._compiled = compiled

    def search(self, string, *args, **kwargs):
        _log_regex("compiled.search", self._compiled, string)
        return self._compiled.search(string, *args, **kwargs)

    def match(self, string, *args, **kwargs):
        _log_regex("compiled.match", self._compiled, string)
        return self._compiled.match(string, *args, **kwargs)

    def fullmatch(self, string, *args, **kwargs):
        _log_regex("compiled.fullmatch", self._compiled, string)
        return self._compiled.fullmatch(string, *args, **kwargs)

    def findall(self, string, *args, **kwargs):
        _log_regex("compiled.findall", self._compiled, string)
        return self._compiled.findall(string, *args, **kwargs)

    def finditer(self, string, *args, **kwargs):
        _log_regex("compiled.finditer", self._compiled, string)
        return self._compiled.finditer(string, *args, **kwargs)

    def __getattr__(self, name):
        return getattr(self._compiled, name)


def _compile(pattern, flags=0):
    compiled = _real_compile(pattern, flags)
    if _pattern_text(pattern) == "(a+)+b":
        return _TrackedPattern(compiled)
    return compiled


re.search = _search
re.match = _match
re.fullmatch = _fullmatch
re.compile = _compile
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import resource
import subprocess

REPORT_PATH = Path("/home/user/report.json")
LOG_PATH = Path("/home/user/server.log")
HOOK_DIR = "/tmp/verifier_hooks"
EVENT_LOG = Path("/tmp/parser_sandbox_events.jsonl")

EXPECTED = {
    "attacker_ip": "203.0.113.42",
    "xor_key": "S3cr3t",
    "admin_timestamp": "1700000055",
    "redos_payload": "redirect=/home&payload=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac",
}


def _load_events():
    events = []
    if EVENT_LOG.exists():
        for line in EVENT_LOG.read_text(errors="replace").splitlines():
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return events


def _report_is_expected():
    try:
        with REPORT_PATH.open() as f:
            data = json.load(f)
        return all(data.get(key) == value for key, value in EXPECTED.items())
    except Exception:
        return False


def test_parser_exists_executes_and_sandboxes_regex():
    scripts = [
        p for p in Path("/home/user").rglob("*.py")
        if p.is_file() and "__pycache__" not in p.parts and p.stat().st_size <= 1024 * 1024
    ]
    assert scripts, "No Python parser script was created under /home/user."

    def score(path):
        text = path.read_text(errors="ignore")
        markers = ("(a+)+b", "setrlimit", "RLIMIT_CPU", "multiprocessing", "report.json")
        return sum(marker in text for marker in markers)

    scripts.sort(key=lambda p: (-score(p), str(p)))
    original_log = LOG_PATH.read_bytes()
    successful = None
    last_errors = []

    for script in scripts:
        LOG_PATH.write_bytes(original_log)
        REPORT_PATH.unlink(missing_ok=True)
        EVENT_LOG.unlink(missing_ok=True)
        env = os.environ.copy()
        env["PYTHONPATH"] = HOOK_DIR + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["VERIFIER_EVENT_LOG"] = str(EVENT_LOG)
        try:
            result = subprocess.run(
                ["python3", str(script)],
                cwd="/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=25,
            )
        except subprocess.TimeoutExpired:
            last_errors.append(f"{script}: parser itself did not terminate")
            continue

        events = _load_events()
        regex_events = [e for e in events if e.get("event") == "regex" and e.get("pattern") == "(a+)+b"]
        limit_events = [
            e for e in events
            if e.get("event") == "setrlimit"
            and e.get("which") == int(resource.RLIMIT_CPU)
            and e.get("soft") == 1
        ]
        limited_pids = {e.get("pid") for e in limit_events}

        queries = []
        for line in original_log.decode("utf-8").splitlines():
            parts = line.split()
            if len(parts) >= 4 and "?" in parts[3]:
                queries.append(parts[3].split("?", 1)[1])

        all_queries_exercised = all(
            any(query in e.get("input", "") for e in regex_events)
            for query in queries
        )
        regex_was_sandboxed = bool(regex_events) and all(
            e.get("pid") in limited_pids for e in regex_events
        )
        regex_was_in_child = bool(regex_events) and all(
            e.get("pid") != result.pid for e in regex_events
        )

        if (result.returncode == 0 and _report_is_expected() and all_queries_exercised
                and regex_was_sandboxed and regex_was_in_child):
            successful = script
            break

        last_errors.append(
            f"{script}: exit={result.returncode}, report={_report_is_expected()}, "
            f"all_queries={all_queries_exercised}, sandboxed={regex_was_sandboxed}, "
            f"child={regex_was_in_child}, stderr={result.stderr[-300:]}"
        )

    LOG_PATH.write_bytes(original_log)
    assert successful is not None, (
        "No submitted Python script regenerated the report while evaluating `(a+)+b` "
        "for the log queries in a separate child process with RLIMIT_CPU set to 1 second. "
        + " | ".join(last_errors)
    )


def test_report_exists():
    assert REPORT_PATH.exists(), f"Report file {REPORT_PATH} is missing. The task requires generating this file."
    assert REPORT_PATH.is_file(), f"{REPORT_PATH} exists but is not a file."


def test_report_content_valid_json():
    with REPORT_PATH.open("r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError as e:
            raise AssertionError(f"Failed to parse {REPORT_PATH} as JSON: {e}")


def test_report_expected_values():
    with REPORT_PATH.open("r") as f:
        data = json.load(f)

    assert "attacker_ip" in data, "Missing 'attacker_ip' in report."
    expected_ip = "203.0.113.42"
    assert data["attacker_ip"] == expected_ip, f"Incorrect attacker_ip. Expected {expected_ip}, got {data['attacker_ip']}."

    assert "xor_key" in data, "Missing 'xor_key' in report."
    expected_key = "S3cr3t"
    assert data["xor_key"] == expected_key, f"Incorrect xor_key. Expected {expected_key}, got {data['xor_key']}."

    assert "admin_timestamp" in data, "Missing 'admin_timestamp' in report."
    expected_ts = "1700000055"
    assert data["admin_timestamp"] == expected_ts, f"Incorrect admin_timestamp. Expected {expected_ts}, got {data['admin_timestamp']}."

    assert "redos_payload" in data, "Missing 'redos_payload' in report."
    expected_payload = "redirect=/home&payload=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac"
    assert data["redos_payload"] == expected_payload, f"Incorrect redos_payload. Expected {expected_payload}, got {data['redos_payload']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
