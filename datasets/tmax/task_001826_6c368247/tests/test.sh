#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import resource
import secrets
import shlex
import string
import subprocess

import pytest

CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
SANITISER_PATH = "/home/user/sanitiser.py"
SERVICE_PATH = "/home/user/.config/systemd/user/log-pipeline.service"
LEGACY_PATH = "/app/legacy_parser"


def no_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(command, data, timeout=5):
    try:
        return subprocess.run(
            command,
            input=data,
            capture_output=True,
            timeout=timeout,
            preexec_fn=no_core_dumps,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Could not execute {command!r}: {exc}")


def test_sanitiser_exists_and_executable():
    assert os.path.exists(SANITISER_PATH), f"Sanitiser script not found at {SANITISER_PATH}"
    assert os.path.isfile(SANITISER_PATH), f"{SANITISER_PATH} is not a file"
    assert os.access(SANITISER_PATH, os.X_OK), f"{SANITISER_PATH} is not executable"

    proc = run([SANITISER_PATH], b"sanitiser executable check\n")
    assert proc.returncode == 0, f"Executable sanitiser exited with {proc.returncode}: {proc.stderr!r}"
    assert proc.stdout == b"sanitiser executable check\n"


def test_sanitiser_against_corpora():
    assert os.path.exists(SANITISER_PATH), f"Sanitiser script missing: {SANITISER_PATH}"

    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_modified = []
    evil_bypassed = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        with open(filepath, "rb") as f:
            original_data = f.read()

        proc = run(["python3", SANITISER_PATH], original_data)
        if proc.returncode != 0 or proc.stdout != original_data:
            clean_modified.append(filename)

    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        with open(filepath, "rb") as f:
            original_data = f.read()

        proc = run(["python3", SANITISER_PATH], original_data)
        if proc.returncode != 0 or proc.stdout.strip() != b"":
            evil_bypassed.append(filename)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail("; ".join(error_msgs))


def make_hidden_cases():
    rng = random.Random(secrets.randbits(128))
    alphabet = string.ascii_letters + string.digits + " .,:;[]{}()_+-=/"
    punctuation = "!@#$%^&*()_+-={}[]:;,.?/\\|~`\"' "
    cases = [b"\n", b"ADMIN_BYPASS=true\n"]

    # Random ordinary log lines and exact length boundaries.
    for _ in range(25):
        length = rng.randint(1, 220)
        text = "".join(rng.choice(alphabet) for _ in range(length))
        cases.append(text.encode("ascii") + b"\n")

    for length in (1, 64, 254, 255, 256, 257, 300, 4096):
        body = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(length))
        cases.append(body.encode("ascii") + b"\n")

    # Place the sensitive token behind varying randomized runs of non-alphanumerics.
    for count in range(0, 9):
        for _ in range(5):
            lead = "L" + "".join(rng.choice(string.ascii_letters) for _ in range(rng.randint(0, 20)))
            separators = "".join(rng.choice(punctuation) for _ in range(count))
            tail = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 30)))
            cases.append((lead + separators + "ADMIN_BYPASS=true" + tail).encode("ascii") + b"\n")

    # An alphanumeric immediately before the token, and multiple token placements.
    for _ in range(15):
        left = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 30)))
        right = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 30)))
        cases.append((left + rng.choice(string.ascii_letters + string.digits) + "ADMIN_BYPASS=true" + right).encode("ascii") + b"\n")

    rng.shuffle(cases)
    return cases


def test_hidden_behavior_matches_legacy_parser():
    assert os.path.isfile(LEGACY_PATH) and os.access(LEGACY_PATH, os.X_OK)
    cases = make_hidden_cases()
    expected_parts = []
    safe_count = 0
    unsafe_count = 0

    # Derive the classification from the shipped legacy program rather than from
    # fixed expected strings. Each candidate is isolated because a vulnerable
    # line terminates the legacy process.
    for payload in cases:
        oracle = run([LEGACY_PATH], payload)
        if oracle.returncode == 0:
            assert oracle.stdout == payload, "Legacy parser unexpectedly transformed a generated safe line"
            expected_parts.append(payload)
            safe_count += 1
        else:
            unsafe_count += 1

    assert safe_count >= 20 and unsafe_count >= 10, "Generated corpus did not exercise both behaviors"
    mixed_input = b"".join(cases)
    expected_output = b"".join(expected_parts)

    for command in (["python3", SANITISER_PATH], [SANITISER_PATH]):
        proc = run(command, mixed_input, timeout=10)
        assert proc.returncode == 0, f"Sanitiser exited with {proc.returncode}: {proc.stderr!r}"
        assert proc.stdout == expected_output, "Sanitiser disagrees with legacy-derived hidden classifications"


def parse_unit_file(content):
    sections = {}
    section = None
    logical_lines = []
    pending = ""
    for raw in content.splitlines():
        line = raw.rstrip()
        if line.endswith("\\"):
            pending += line[:-1]
            continue
        logical_lines.append(pending + line)
        pending = ""
    if pending:
        logical_lines.append(pending)

    for raw in logical_lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith(("#", ";")):
            continue
        match = re.fullmatch(r"\[([^]]+)\]", stripped)
        if match:
            section = match.group(1)
            sections.setdefault(section, {})
            continue
        assert section is not None and "=" in raw, f"Malformed unit line: {raw!r}"
        key, value = raw.split("=", 1)
        sections[section].setdefault(key.strip(), []).append(value.strip())
    return sections


def test_systemd_service_updated():
    assert os.path.exists(SERVICE_PATH), f"Service file missing: {SERVICE_PATH}"
    with open(SERVICE_PATH, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert re.search(r"^After=.*tunnel\.service", content, re.MULTILINE), \
        "Service file does not contain 'After=tunnel.service'."
    exec_start_match = re.search(r"^ExecStart=(.*)$", content, re.MULTILINE)
    assert exec_start_match, "Service file missing ExecStart directive."
    exec_start_line = exec_start_match.group(1)
    assert re.search(r"python3\s+/home/user/sanitiser\.py", exec_start_line) or \
           re.search(r"/home/user/sanitiser\.py", exec_start_line), \
           "ExecStart does not invoke the sanitiser script."
    assert "|" in exec_start_line, "ExecStart does not contain a pipe."
    assert "/app/legacy_parser" in exec_start_line, "ExecStart does not invoke the legacy parser."
    assert exec_start_line.find("sanitiser.py") < exec_start_line.find("/app/legacy_parser"), \
        "Sanitiser must be piped into the legacy parser."

    # Validate dependency directives in their actual systemd section.
    unit = parse_unit_file(content)
    assert "Unit" in unit and "Service" in unit, "Unit file needs [Unit] and [Service] sections"
    after = sum((shlex.split(v) for v in unit["Unit"].get("After", [])), [])
    requires = sum((shlex.split(v) for v in unit["Unit"].get("Requires", [])), [])
    assert "tunnel.service" in after, "[Unit] must order this service After=tunnel.service"
    assert "tunnel.service" in requires, "[Unit] must Require tunnel.service, not merely order after it"

    exec_values = unit["Service"].get("ExecStart", [])
    assert len(exec_values) == 1, "[Service] must have one ExecStart command"
    outer = shlex.split(exec_values[0], posix=True)
    assert len(outer) >= 3 and os.path.basename(outer[0]) in ("bash", "sh") and outer[1] == "-c", \
        "ExecStart must run the pipeline through a shell with -c"
    shell_command = outer[2]
    lexer = shlex.shlex(shell_command, posix=True, punctuation_chars="|;&")
    lexer.whitespace_split = True
    tokens = list(lexer)
    assert not any(tok in (";", "&", "&&", "||") for tok in tokens), \
        "ExecStart must be a single pipeline"

    segments = []
    current = []
    for token in tokens:
        if token == "|":
            assert current, "Empty command in ExecStart pipeline"
            segments.append(current)
            current = []
        else:
            current.append(token)
    assert current, "Empty final command in ExecStart pipeline"
    segments.append(current)

    parser_positions = [i for i, seg in enumerate(segments) if seg and seg[0] == LEGACY_PATH]
    assert len(parser_positions) == 1, "The pipeline must execute /app/legacy_parser as a command"
    parser_index = parser_positions[0]
    assert parser_index > 0, "The parser must receive input from the sanitiser"
    previous = segments[parser_index - 1]
    direct = previous and previous[0] == SANITISER_PATH
    via_python = len(previous) >= 2 and os.path.basename(previous[0]) == "python3" and previous[1] == SANITISER_PATH
    assert direct or via_python, "The command immediately before /app/legacy_parser must be the sanitiser"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
