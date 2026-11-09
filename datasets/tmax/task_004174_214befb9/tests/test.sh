#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import uuid

OUTPUT = "/home/user/output/redacted_failed.log"
EXPECTED_CONTENT = [
    "2023-11-01T08:15:22 INFO [api.legacy-system.net] Initializing connection for user=admin cc=XXXX-XXXX-XXXX-XXXX",
    "2023-11-01T08:15:23 ERROR [api.legacy-system.net] CERT_CHAIN_FAIL Expired certificate in chain",
    "2023-11-01T08:15:25 INFO [api.legacy-system.net] Retrying connection without tls...",
    "2023-11-01T08:20:01 INFO [analytics.tracker.io] Data sync cc=XXXX-XXXX-XXXX-XXXX",
    "2023-11-01T08:20:02 ERROR [analytics.tracker.io] CERT_CHAIN_FAIL Self-signed cert",
]


def test_scripts_exist_and_executable():
    parse_logs = "/home/user/parse_logs.sh"
    run_sandbox = "/home/user/run_sandbox.sh"

    assert os.path.isfile(parse_logs), f"Expected script {parse_logs} does not exist."
    assert os.path.isfile(run_sandbox), f"Expected script {run_sandbox} does not exist."

    assert os.access(parse_logs, os.X_OK), f"{parse_logs} is not executable."
    assert os.access(run_sandbox, os.X_OK), f"{run_sandbox} is not executable."


def test_run_sandbox_content():
    run_sandbox = "/home/user/run_sandbox.sh"
    with open(run_sandbox, "r") as f:
        content = f.read()

    assert "bwrap" in content, "run_sandbox.sh must use bwrap."
    assert "--ro-bind" in content, "run_sandbox.sh must use --ro-bind to mount / read-only."
    assert "--bind" in content, "run_sandbox.sh must use --bind to mount the output directory."
    assert "--unshare-all" in content, "run_sandbox.sh must use --unshare-all."


def _has_sequence(args, sequence):
    n = len(sequence)
    return any(args[i:i+n] == sequence for i in range(len(args) - n + 1))


def test_run_sandbox_actually_invokes_bwrap_and_generates_output():
    # Replace bwrap briefly with a recording compatibility shim. This verifies the
    # wrapper's real invocation even on a test host where user namespaces are disabled.
    bwrap = "/usr/bin/bwrap"
    backup = "/usr/bin/bwrap.verifier-real"
    record = "/tmp/verifier-bwrap-args"
    assert os.path.isfile(bwrap), "bubblewrap is not installed"
    if os.path.exists(record):
        os.unlink(record)
    if os.path.exists(backup):
        os.unlink(backup)

    original_mode = stat.S_IMODE(os.stat(bwrap).st_mode)
    os.replace(bwrap, backup)
    shim = r'''#!/usr/bin/python3
import os, subprocess, sys
args = sys.argv[1:]
with open("/tmp/verifier-bwrap-args", "wb") as f:
    f.write(b"\0".join(a.encode() for a in args))
try:
    i = args.index("/home/user/parse_logs.sh")
except ValueError:
    sys.exit(97)
sys.exit(subprocess.call(args[i:]))
'''
    try:
        with open(bwrap, "w") as f:
            f.write(shim)
        os.chmod(bwrap, 0o755)
        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
        result = subprocess.run(
            ["/home/user/run_sandbox.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    finally:
        if os.path.exists(bwrap):
            os.unlink(bwrap)
        os.replace(backup, bwrap)
        os.chmod(bwrap, original_mode)

    assert result.returncode == 0, (
        "run_sandbox.sh failed when its bwrap invocation was executed:\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(record), "run_sandbox.sh did not actually execute bwrap"
    with open(record, "rb") as f:
        raw = f.read()
    args = [part.decode() for part in raw.split(b"\0")] if raw else []

    assert _has_sequence(args, ["--ro-bind", "/", "/"]), (
        "bwrap must mount the root filesystem read-only with '--ro-bind / /'"
    )
    assert "--unshare-all" in args, "bwrap must be invoked with --unshare-all"
    assert (
        _has_sequence(args, ["--dev", "/dev"])
        or _has_sequence(args, ["--dev-bind", "/dev", "/dev"])
    ), "bwrap must mount /dev appropriately"

    writable_output = False
    for i in range(len(args) - 2):
        if args[i] == "--bind":
            source = os.path.normpath(args[i + 1])
            destination = os.path.normpath(args[i + 2])
            if source == "/home/user/output" and destination == "/home/user/output":
                writable_output = True
                break
    assert writable_output, (
        "bwrap must bind /home/user/output read-write onto /home/user/output"
    )
    assert _has_sequence(
        args, ["/home/user/parse_logs.sh", "/home/user/app_logs/server.log"]
    ), "bwrap must execute parse_logs.sh on /home/user/app_logs/server.log"
    assert os.path.isfile(OUTPUT), "Executing run_sandbox.sh did not generate the output file"


def test_redacted_failed_log_content():
    output_file = "/home/user/output/redacted_failed.log"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist. Did you run the sandbox script?"

    with open(output_file, "r") as f:
        content = f.read().strip().split('\n')

    expected_content = EXPECTED_CONTENT

    assert len(content) == len(expected_content), f"Expected {len(expected_content)} lines in {output_file}, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_content)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_no_unredacted_cc_numbers():
    output_file = "/home/user/output/redacted_failed.log"
    if not os.path.isfile(output_file):
        return

    with open(output_file, "r") as f:
        content = f.read()

    cc_pattern = re.compile(r'\b\d{4}-\d{4}-\d{4}-\d{4}\b')
    unredacted = cc_pattern.findall(content)

    assert len(unredacted) == 0, f"Found unredacted credit card numbers in the output: {unredacted}"


def test_parse_logs_on_unseen_input():
    token = uuid.uuid4().hex
    failed_a = f"alpha-{token}.invalid"
    failed_b = f"beta-{token}.invalid"
    good = f"good-{token}.invalid"
    lines = [
        f"2026-07-03T09:00:00 INFO [{failed_a}] before cc=4000-1111-2222-3333",
        f"2026-07-03T09:00:01 INFO [{good}] keep-private cc=5000-1111-2222-3333",
        f"2026-07-03T09:00:02 ERROR [{failed_b}] CERT_CHAIN_FAIL unknown issuer",
        f"2026-07-03T09:00:03 INFO [{failed_a}] middle event",
        f"2026-07-03T09:00:04 ERROR [{failed_a}] CERT_CHAIN_FAIL expired",
        f"2026-07-03T09:00:05 INFO [{good}] final good event",
        f"2026-07-03T09:00:06 WARN [{failed_b}] after cc=6000-7777-8888-9999 and cc=1234-5678-9012-3456",
    ]

    domain_re = re.compile(r'\[([^\]]+)\]')
    cc_re = re.compile(r'\d{4}-\d{4}-\d{4}-\d{4}')
    failed_domains = {
        domain_re.search(line).group(1)
        for line in lines
        if "CERT_CHAIN_FAIL" in line and domain_re.search(line)
    }
    expected = [
        cc_re.sub("XXXX-XXXX-XXXX-XXXX", line)
        for line in lines
        if domain_re.search(line) and domain_re.search(line).group(1) in failed_domains
    ]

    canonical = "\n".join(EXPECTED_CONTENT) + "\n"
    fd, path = tempfile.mkstemp(prefix="unseen-server-", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines) + "\n")
        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
        result = subprocess.run(
            ["/home/user/parse_logs.sh", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            "parse_logs.sh failed on an unseen input:\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(OUTPUT), "parse_logs.sh did not create redacted_failed.log"
        with open(OUTPUT, "r") as f:
            actual = f.read().splitlines()
        assert actual == expected, (
            "parse_logs.sh did not correlate failed domains and redact cards correctly "
            f"on an unseen input.\nExpected: {expected!r}\nActual: {actual!r}"
        )
    finally:
        if os.path.exists(path):
            os.unlink(path)
        os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
        with open(OUTPUT, "w") as f:
            f.write(canonical)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
