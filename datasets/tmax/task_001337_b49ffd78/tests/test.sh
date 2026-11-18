#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shlex
import shutil
import stat
import string
import subprocess

import pytest

DEPLOY = "/home/user/deploy.sh"
SOURCE = "/home/user/sanitizer.go"
BINARY = "/home/user/sanitizer_bin"
TUNNEL = "/home/user/tunnel_cmd.txt"


@pytest.fixture(scope="session", autouse=True)
def run_deploy_script():
    assert os.path.isfile(DEPLOY), f"Deploy script {DEPLOY} does not exist."
    st = os.stat(DEPLOY)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deploy script {DEPLOY} is not executable."
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} does not exist."

    # The required outputs must be produced by deploy.sh, not merely left in place.
    for path in (BINARY, TUNNEL):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    result = subprocess.run(
        ["/bin/bash", "-x", DEPLOY],
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"deploy.sh failed with status {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    # Bash xtrace proves that the export was executed, rather than merely appearing
    # in a comment. Support both `export EDGE_NODE=value` and assignment plus export.
    trace = result.stderr
    exported = re.search(
        r"(?m)^\+\s+(?:export\s+EDGE_NODE(?:=active_secure)?|declare\s+-x\s+EDGE_NODE(?:=active_secure)?)\s*$",
        trace,
    )
    assigned = re.search(
        r"(?m)^\+\s+(?:EDGE_NODE=active_secure|(?:export|declare\s+-x)\s+EDGE_NODE=active_secure)\s*$",
        trace,
    )
    assert exported and assigned, "deploy.sh must export EDGE_NODE=active_secure when run."


def test_deploy_script_exists_and_executable():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"Deploy script {deploy_script} does not exist."
    st = os.stat(deploy_script)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deploy script {deploy_script} is not executable."


def test_sanitizer_source_exists():
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} does not exist."
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"(?m)^\s*package\s+main\b", source), "sanitizer.go is not a Go main package."


def test_tunnel_cmd_content():
    tunnel_file = "/home/user/tunnel_cmd.txt"
    assert os.path.isfile(tunnel_file), f"Tunnel command file {tunnel_file} does not exist."

    with open(tunnel_file, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Preserve the original forwarding/flag assertions.
    assert re.search(r'-L\s*8080:(127\.0\.0\.1|localhost):9090', content), f"Missing or incorrect port forwarding in {tunnel_file}."
    assert re.search(r'-N', content), f"Missing -N flag in {tunnel_file}."
    assert re.search(r'-f', content), f"Missing -f flag in {tunnel_file}."

    # Also require one syntactically coherent SSH invocation with a destination and
    # no shell operators or remote command.
    assert "\n" not in content and "\r" not in content, "Tunnel file must contain exactly one command."
    assert not re.search(r"[;&|<>`$]", content), "Tunnel command must not contain shell operators or substitutions."
    try:
        tokens = shlex.split(content, posix=True)
    except ValueError as exc:
        pytest.fail(f"Tunnel command is not valid shell syntax: {exc}")
    assert tokens and os.path.basename(tokens[0]) == "ssh", "Tunnel command must invoke ssh."

    seen_n = seen_f = seen_l = False
    i = 1
    while i < len(tokens) and tokens[i].startswith("-"):
        token = tokens[i]
        if token == "--":
            i += 1
            break
        chars = token[1:]
        assert chars, "Invalid empty SSH option."
        j = 0
        while j < len(chars):
            option = chars[j]
            if option == "N":
                seen_n = True
                j += 1
            elif option == "f":
                seen_f = True
                j += 1
            elif option == "L":
                if j + 1 < len(chars):
                    forward = chars[j + 1:]
                else:
                    i += 1
                    assert i < len(tokens), "-L requires a forwarding specification."
                    forward = tokens[i]
                assert forward in ("8080:localhost:9090", "8080:127.0.0.1:9090"), "Incorrect SSH forwarding specification."
                seen_l = True
                j = len(chars)
            else:
                pytest.fail(f"Unexpected SSH option '-{option}' in tunnel command.")
        i += 1

    assert seen_n and seen_f and seen_l, "SSH command must include -N, -f, and the required -L forwarding."
    assert len(tokens[i:]) == 1, "SSH command must have one destination and no remote command."
    assert tokens[i] and not tokens[i].startswith("-"), "SSH destination is missing."


def test_tamper_frames_content():
    tamper_file = "/home/user/tamper_frames.txt"
    assert os.path.isfile(tamper_file), f"Tamper frames file {tamper_file} does not exist."

    with open(tamper_file, "r") as f:
        content = f.read().strip()

    assert content == "42,43,44,45,46", f"Expected '42,43,44,45,46' in {tamper_file}, got '{content}'."


def run_payload(payload):
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    try:
        return subprocess.run([BINARY], input=payload, capture_output=True, timeout=3).returncode
    except subprocess.TimeoutExpired:
        pytest.fail("sanitizer_bin timed out while validating a payload.")


def test_sanitizer_bin_corpus():
    sanitizer_bin = "/home/user/sanitizer_bin"
    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary {sanitizer_bin} does not exist. Did deploy.sh compile it?"

    st = os.stat(sanitizer_bin)
    assert bool(st.st_mode & stat.S_IXUSR), f"Sanitizer binary {sanitizer_bin} is not executable."
    with open(sanitizer_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer_bin must be a compiled executable, not a script."

    clean_corpus_dir = "/app/corpus/clean"
    evil_corpus_dir = "/app/corpus/evil"
    clean_failed = []
    evil_failed = []

    if os.path.isdir(clean_corpus_dir):
        for filename in os.listdir(clean_corpus_dir):
            filepath = os.path.join(clean_corpus_dir, filename)
            if os.path.isfile(filepath):
                with open(filepath, "rb") as f:
                    payload = f.read()
                if run_payload(payload) != 0:
                    clean_failed.append(filename)

    if os.path.isdir(evil_corpus_dir):
        for filename in os.listdir(evil_corpus_dir):
            filepath = os.path.join(evil_corpus_dir, filename)
            if os.path.isfile(filepath):
                with open(filepath, "rb") as f:
                    payload = f.read()
                if run_payload(payload) == 0:
                    evil_failed.append(filename)

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} clean payloads rejected (expected accepted): {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} evil payloads accepted (expected rejected): {', '.join(evil_failed)}")
    assert not error_messages, " | ".join(error_messages)


def test_sanitizer_generated_payloads():
    # Generate fresh cases after the agent has finished, so corpus contents cannot
    # be hardcoded. Expected results are derived here from the stated rules.
    rng = random.Random(secrets.randbits(128))
    alphabet = string.ascii_letters + string.digits

    valid_payloads = []
    invalid_payloads = []
    for _ in range(60):
        device = "".join(rng.choice(alphabet) for _ in range(8))
        ip = ".".join(str(rng.randint(0, 255)) for _ in range(4))
        temperature = rng.uniform(-50.0, 150.0)
        good = {
            "device_id": device,
            "ip_address": ip,
            "temperature": temperature,
            "ignored_extra": {"nonce": secrets.token_hex(8), "values": [1, True, None]},
        }
        valid_payloads.append(json.dumps(good, separators=(",", ":")))

        bad = dict(good)
        mutation = rng.randrange(8)
        if mutation == 0:
            bad["device_id"] = device[:rng.randrange(0, 8)]
        elif mutation == 1:
            pos = rng.randrange(8)
            bad["device_id"] = device[:pos] + rng.choice("-_!@") + device[pos + 1:]
        elif mutation == 2:
            bad["ip_address"] = f"{rng.randint(256, 999)}.{rng.randint(0,255)}.{rng.randint(0,255)}.{rng.randint(0,255)}"
        elif mutation == 3:
            bad["ip_address"] = f"{rng.randint(0,255)}.{rng.randint(0,255)}.{rng.randint(0,255)}"
        elif mutation == 4:
            bad["ip_address"] = ip + ";echo injected"
        elif mutation == 5:
            bad["temperature"] = rng.uniform(150.0001, 10000.0)
        elif mutation == 6:
            bad["temperature"] = rng.uniform(-10000.0, -50.0001)
        else:
            bad["temperature"] = str(temperature)
        invalid_payloads.append(json.dumps(bad, separators=(",", ":")))

    valid_payloads.extend([
        '{"device_id":"Ab12Cd34","ip_address":"0.0.0.0","temperature":-50}',
        '{"device_id":"Z9y8X7w6","ip_address":"255.255.255.255","temperature":150.0,"extra":true}',
        '  {"device_id":"00000000","ip_address":"127.0.0.1","temperature":0}\n',
    ])
    invalid_payloads.extend([
        "", "not-json", "[]", "null", "{}", "{", 
        '{"device_id":"Ab12Cd34","ip_address":"127.0.0.1"}',
        '{"device_id":"Ab12Cd34","temperature":20}',
        '{"ip_address":"127.0.0.1","temperature":20}',
        '{"device_id":12345678,"ip_address":"127.0.0.1","temperature":20}',
        '{"device_id":"Ab12Cd34","ip_address":1234,"temperature":20}',
        '{"device_id":"Ab12Cd34","ip_address":"127.0.0.1","temperature":null}',
        '{"device_id":"Ab12Cd34","ip_address":"127.0.0.1","temperature":20} trailing',
        '{"device_id":"Ab12Cd34","ip_address":"127.0.0.1","temperature":20}{"x":1}',
        '{"device_id":"Ab12Cd34","ip_address":"127.0.0.1.5","temperature":20}',
        '{"device_id":"Ab12Cd34","ip_address":"127.0.-1.1","temperature":20}',
        '{"device_id":"Ab12Cd34","ip_address":"::1","temperature":20}',
    ])

    failures = []
    for payload in valid_payloads:
        code = run_payload(payload)
        if code != 0:
            failures.append(f"valid payload returned {code}: {payload!r}")
    for payload in invalid_payloads:
        code = run_payload(payload)
        if code != 1:
            failures.append(f"invalid payload returned {code}, expected 1: {payload!r}")
    assert not failures, "\n".join(failures[:10])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
