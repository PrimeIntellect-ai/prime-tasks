#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import string
import subprocess
import urllib.error
import urllib.request

AGENT_PATH = "/home/user/transform_backend"
ORACLE_PATH = "/tests/oracle_transform"
UNIT_PATH = "/home/user/.config/systemd/user/fcgi-backend.service"
ENABLE_PATH = "/home/user/.config/systemd/user/default.target.wants/fcgi-backend.service"


def test_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"The executable {AGENT_PATH} is missing."
    assert os.access(AGENT_PATH, os.X_OK), f"The file {AGENT_PATH} is not executable."
    assert os.path.isfile(ORACLE_PATH), f"Oracle program {ORACLE_PATH} missing."
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Submitted executable is the oracle file."
    with open(AGENT_PATH, "rb") as agent, open(ORACLE_PATH, "rb") as oracle:
        assert agent.read() != oracle.read(), "Submitted executable is byte-identical to the oracle."


def test_systemd_user_service():
    assert os.path.isfile(UNIT_PATH), f"Required user service {UNIT_PATH} is missing."

    section = None
    service_lines = []
    with open(UNIT_PATH, encoding="utf-8") as unit:
        for raw_line in unit:
            line = raw_line.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].strip()
            elif section == "Service":
                service_lines.append(line)

    exec_starts = []
    environment = {}
    for line in service_lines:
        key, sep, value = line.partition("=")
        if not sep:
            continue
        if key.strip() == "ExecStart":
            exec_starts.append(value.strip())
        elif key.strip() == "Environment":
            for assignment in shlex.split(value):
                name, eq, setting = assignment.partition("=")
                if eq:
                    environment[name] = setting

    assert any(AGENT_PATH in command for command in exec_starts), \
        f"The service ExecStart must manage {AGENT_PATH}."
    assert environment.get("LANG") == "en_US.UTF-8", \
        "The service must set LANG=en_US.UTF-8."
    assert environment.get("TZ") == "UTC", "The service must set TZ=UTC."
    assert environment.get("PORT") == "9000", "The service must set PORT=9000."

    assert os.path.islink(ENABLE_PATH), \
        "fcgi-backend.service is not enabled for the user default target."
    assert os.path.realpath(ENABLE_PATH) == os.path.realpath(UNIT_PATH), \
        "The enabled fcgi-backend.service link does not reference the required unit."


def test_nginx_proxy():
    data = b"aabbbcc"
    req = urllib.request.Request("http://127.0.0.1:8080/api", data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            body = response.read().decode("utf-8").strip()
            assert len(body) > 0, "Received empty response from Nginx."
            assert body == "a2b3c2", f"Expected RLE response 'a2b3c2', got {body!r}."
    except urllib.error.HTTPError as exc:
        assert False, f"Nginx proxy returned HTTP error: {exc.code}"
    except urllib.error.URLError as exc:
        assert False, f"Failed to connect to Nginx proxy: {exc.reason}"
    except Exception as exc:
        assert False, f"Nginx proxy test failed: {exc}"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle program {ORACLE_PATH} missing."
    assert os.path.isfile(AGENT_PATH), f"Agent program {AGENT_PATH} missing."

    random.seed(42)
    chars = string.ascii_letters + string.digits
    inputs = [
        "a",
        "aaabbc",
        "a" * 9,
        "a" * 10,
        "a" * 11,
        "a" * 25 + "b" * 10 + "c",
        "A" * 500,
    ]
    for _ in range(1000):
        length = random.randint(1, 500)
        inputs.append("".join(random.choices(chars, k=length)))

    env = os.environ.copy()
    env["LANG"] = "en_US.UTF-8"
    env["TZ"] = "UTC"

    for test_input in inputs:
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH],
                input=test_input,
                text=True,
                capture_output=True,
                env=env,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            assert False, f"Oracle program timed out on input: {test_input}"

        try:
            agent_proc = subprocess.run(
                [AGENT_PATH],
                input=test_input,
                text=True,
                capture_output=True,
                env=env,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            assert False, f"Agent program timed out on input: {test_input}"

        assert oracle_proc.returncode == 0, \
            f"Oracle program failed on input: {test_input!r}"
        assert agent_proc.returncode == 0, \
            f"Agent program crashed (return code {agent_proc.returncode}) on input: {test_input!r}"
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on input {test_input!r}.\n"
            f"Expected (Oracle): {oracle_proc.stdout!r}\n"
            f"Got (Agent): {agent_proc.stdout!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
