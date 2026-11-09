#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from pathlib import Path


def run_checked(argv, timeout=20):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command {argv!r} failed with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def expected_outbox(entries):
    return "".join(
        f"TO: {recipient}\nSUBJECT: {subject}\nBODY: {message}\n---\n"
        for recipient, subject, message in entries
    )


def test_send_alert_exp_exists_executable_and_works():
    path = Path("/home/user/send_alert.exp")
    assert path.exists(), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"

    token = secrets.token_hex(10)
    recipient = f"verify-{token}@local.domain"
    subject = f"Dynamic subject {token}"
    message = f"Dynamic message with spaces [{token}]"
    outbox = Path("/home/user/outbox.txt")
    outbox.unlink(missing_ok=True)

    run_checked([str(path), recipient, subject, message])
    assert outbox.exists(), "send_alert.exp did not cause the legacy mailer to create the outbox"
    assert outbox.read_text() == expected_outbox([(recipient, subject, message)])

    # Verify that the expect script really starts and drives the configured legacy
    # mailer rather than merely synthesizing its output itself.
    legacy = Path("/home/user/legacy_mailer.py")
    original_bytes = legacy.read_bytes()
    original_mode = legacy.stat().st_mode
    record = Path(f"/tmp/mailer_probe_{token}.json")
    probe = """#!/usr/bin/env python3
import json
import sys

RECORD = %r

def ask(prompt):
    print(prompt, end="", flush=True)
    return sys.stdin.readline().rstrip("\\r\\n")

recipient = ask("Recipient: ")
subject = ask("Subject: ")
message = ask("Message: ")
confirm = ask("Send? (y/n): ")
with open(RECORD, "w") as f:
    json.dump([recipient, subject, message, confirm], f)
print("Sent successfully." if confirm.lower() == "y" else "Aborted.")
""" % str(record)

    probe_recipient = f"probe-{token}@local.domain"
    probe_subject = f"Probe subject {token}"
    probe_message = f"Probe message {token}"
    try:
        legacy.write_text(probe)
        os.chmod(legacy, 0o755)
        run_checked([str(path), probe_recipient, probe_subject, probe_message])
    finally:
        legacy.write_bytes(original_bytes)
        os.chmod(legacy, original_mode)

    assert record.exists(), "send_alert.exp did not execute /home/user/legacy_mailer.py"
    assert json.loads(record.read_text()) == [
        probe_recipient,
        probe_subject,
        probe_message,
        "y",
    ]


def test_log_monitor_binary_exists():
    path = Path("/home/user/log_monitor/target/release/log_monitor")
    assert path.exists(), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with path.open("rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled Linux binary"


def test_config_fw_sh_idempotent_and_preserves_unrelated_rules():
    path = Path("/home/user/config_fw.sh")
    assert path.exists(), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"

    conf = Path("/home/user/firewall.conf")
    forward_rule = "FORWARD PORT 8080 TO 9090"
    block_rule = "BLOCK PORT 22"

    # From an empty state, repeated runs must produce only the two requested rules.
    conf.unlink(missing_ok=True)
    for _ in range(3):
        run_checked([str(path)])
    assert conf.exists(), f"{conf} was not created by the script"
    lines = [line.strip() for line in conf.read_text().splitlines() if line.strip()]
    assert lines.count(forward_rule) == 1
    assert lines.count(block_rule) == 1
    assert sorted(lines) == sorted([forward_rule, block_rule]), (
        f"Unexpected lines were added to {conf}: {lines!r}"
    )

    # Rules added by another process must survive, while duplicate managed rules
    # are reduced to one instance each on every run.
    token = secrets.token_hex(8)
    unrelated = [f"ALLOW SERVICE {token}", f"AUDIT TARGET {token}"]
    conf.write_text(
        "\n".join([
            unrelated[0],
            forward_rule,
            block_rule,
            forward_rule,
            unrelated[1],
            block_rule,
        ]) + "\n"
    )
    for _ in range(3):
        run_checked([str(path)])

    lines = [line.strip() for line in conf.read_text().splitlines() if line.strip()]
    assert lines.count(forward_rule) == 1
    assert lines.count(block_rule) == 1
    assert [line for line in lines if line not in (forward_rule, block_rule)] == unrelated
    assert len(lines) == 4, f"Configuration contains unexpected lines: {lines!r}"


def test_log_monitor_invokes_expect_for_dynamic_matching_lines_only():
    binary = Path("/home/user/log_monitor/target/release/log_monitor")
    expect_path = Path("/home/user/send_alert.exp")
    token = secrets.token_hex(10)
    log_path = Path(f"/tmp/dynamic_log_{token}.log")
    record_path = Path(f"/tmp/expect_calls_{token}.jsonl")

    matching = [
        f"prefix-{token} [CRITICAL] first dynamic event",
        f"[CRITICAL] second event {token} with spaces",
        f"third-{token}[CRITICAL]embedded marker",
    ]
    log_lines = [
        f"[INFO] startup {token}",
        matching[0],
        f"[critical] wrong case {token}",
        f"[CRITICALITY] near miss {token}",
        matching[1],
        f"ordinary line {token}",
        matching[2],
    ]
    log_path.write_text("\n".join(log_lines))

    original_bytes = expect_path.read_bytes()
    original_mode = expect_path.stat().st_mode
    spy = """#!/usr/bin/env python3
import json
import sys
with open(%r, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
""" % str(record_path)

    try:
        expect_path.write_text(spy)
        os.chmod(expect_path, 0o755)
        result = run_checked([str(binary), str(log_path)])
    finally:
        expect_path.write_bytes(original_bytes)
        os.chmod(expect_path, original_mode)

    calls = []
    if record_path.exists():
        calls = [json.loads(line) for line in record_path.read_text().splitlines()]
    expected_calls = [
        ["oncall@local.domain", "Critical System Alert", line]
        for line in matching
    ]
    assert calls == expected_calls, (
        "log_monitor did not invoke /home/user/send_alert.exp exactly once for "
        f"each dynamically generated matching line. Expected {expected_calls!r}, got {calls!r}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_log_monitor_dynamic_end_to_end():
    binary = Path("/home/user/log_monitor/target/release/log_monitor")
    outbox = Path("/home/user/outbox.txt")
    token = secrets.token_hex(10)
    log_path = Path(f"/tmp/end_to_end_{token}.log")
    matching = [
        f"host-{token}: [CRITICAL] randomized failure one",
        f"[CRITICAL] randomized failure two {token}",
    ]
    log_path.write_text(
        "\n".join([
            f"[INFO] {token}",
            matching[0],
            f"[WARNING] [CRIT] {token}",
            matching[1],
        ]) + "\n"
    )
    outbox.unlink(missing_ok=True)
    run_checked([str(binary), str(log_path)])
    assert outbox.exists()
    expected = expected_outbox([
        ("oncall@local.domain", "Critical System Alert", line)
        for line in matching
    ])
    assert outbox.read_text() == expected


def test_log_monitor_original_fixture_integration():
    binary_path = "/home/user/log_monitor/target/release/log_monitor"
    log_path = "/home/user/test_system.log"
    outbox_path = Path("/home/user/outbox.txt")
    outbox_path.unlink(missing_ok=True)

    result = run_checked([binary_path, log_path])
    assert outbox_path.exists(), f"{outbox_path} was not created after running log_monitor"

    expected_content = (
        "TO: oncall@local.domain\n"
        "SUBJECT: Critical System Alert\n"
        "BODY: [CRITICAL] Database connection lost\n"
        "---\n"
        "TO: oncall@local.domain\n"
        "SUBJECT: Critical System Alert\n"
        "BODY: [CRITICAL] OOM Killer invoked\n"
        "---\n"
    )
    content = outbox_path.read_text()
    assert content == expected_content, (
        f"Outbox content did not match expected.\nExpected:\n{expected_content}\nGot:\n{content}\n"
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
