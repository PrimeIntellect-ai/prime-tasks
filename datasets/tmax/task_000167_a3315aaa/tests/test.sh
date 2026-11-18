#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import string
import subprocess
from pathlib import Path

import pytest


def test_link_drops_count():
    path = "/home/user/link_drops.txt"
    assert os.path.exists(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "7", f"Expected '7' in {path}, but found '{content}'"


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_analyzer_oracle"
    agent_path = "/home/user/net_analyzer"

    assert os.path.exists(agent_path), f"Agent program missing: {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent program is not executable: {agent_path}"

    random.seed(42)

    def generate_input():
        parts = []
        if random.random() < 0.5:
            parts.append(f"{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(0,255)}")
        if random.random() < 0.5:
            parts.append(f"{random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}")

        for _ in range(random.randint(1, 5)):
            parts.append(''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(2, 10))))

        random.shuffle(parts)
        res = " ".join(parts)
        if len(res) < 10:
            res += " " + ''.join(random.choices(string.ascii_letters, k=10))
        return res[:100]

    for _ in range(1000):
        test_input = generate_input()

        oracle_proc = subprocess.run(
            [oracle_path], input=test_input, text=True, capture_output=True
        )
        agent_proc = subprocess.run(
            [agent_path], input=test_input, text=True, capture_output=True
        )

        assert oracle_proc.returncode == 0, f"Oracle failed on input: {test_input}"
        assert agent_proc.returncode == 0, f"Agent failed on input: {test_input}"
        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Mismatch on input: '{test_input}'\n"
            f"Oracle output: '{oracle_proc.stdout}'\n"
            f"Agent output: '{agent_proc.stdout}'"
        )


def test_go_source_and_independent_behavior():
    source_path = Path("/home/user/net_analyzer.go")
    agent_path = Path("/home/user/net_analyzer")
    oracle_path = Path("/app/legacy_analyzer_oracle")
    rebuilt_path = Path("/tmp/net_analyzer_rebuilt")

    assert source_path.is_file(), f"Go source missing: {source_path}"
    assert agent_path.is_file(), f"Agent program missing: {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent program is not executable: {agent_path}"
    assert agent_path.read_bytes()[:4] == b"\x7fELF", "net_analyzer is not a compiled executable"

    build = subprocess.run(
        ["go", "build", "-o", str(rebuilt_path), str(source_path)],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert build.returncode == 0, f"net_analyzer.go does not build:\n{build.stdout}\n{build.stderr}"

    oracle_bytes = oracle_path.read_bytes()
    oracle_mode = stat.S_IMODE(oracle_path.stat().st_mode)
    agent_bytes = agent_path.read_bytes()
    assert agent_bytes != oracle_bytes, "net_analyzer is byte-identical to the legacy oracle"
    assert not agent_bytes.startswith(oracle_bytes), "net_analyzer is the legacy oracle with trailing data"

    ip_re = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", re.ASCII)

    def expected(data):
        if data == "":
            return ""
        line = data.split("\n", 1)[0]
        if line.endswith("\r"):
            line = line[:-1]
        line = line.upper()
        ips = ip_re.findall(line)
        line = line.replace(" ", "-")
        if ips:
            line += "-" + "-".join(ips)
        return line + "\n"

    cases = [
        "",
        "\n",
        "router online",
        "2026-09-11 12:34:56 src 10.2.3.4 link down",
        "a 1.2.3.4 b 255.255.255.255 c",
        "multiple   spaces 10.0.0.1",
        "tabs\tremain 8.8.8.8",
        "x1.2.3.4y boundary 1.2.3.4!",
        "999.888.777.666 unusual address",
        "first line 10.0.0.1\nignored second line 9.9.9.9",
        "mixed-Case_DIAGNOSTIC at 00:05:09 from 172.16.0.7\r\nnext",
    ]

    # The submitted executable and a fresh build of the submitted Go source must
    # work without the oracle being present, and are checked against independently
    # derived answers.
    oracle_path.unlink()
    try:
        for executable in (agent_path, rebuilt_path):
            for test_input in cases:
                proc = subprocess.run(
                    [str(executable)],
                    input=test_input,
                    text=True,
                    capture_output=True,
                    timeout=5,
                )
                assert proc.returncode == 0, (
                    f"{executable} failed on {test_input!r}: {proc.stderr}"
                )
                assert proc.stdout == expected(test_input), (
                    f"{executable} mismatch on {test_input!r}: "
                    f"expected {expected(test_input)!r}, got {proc.stdout!r}"
                )
    finally:
        oracle_path.write_bytes(oracle_bytes)
        os.chmod(oracle_path, oracle_mode)


def test_expect_script_interaction():
    script_path = Path("/home/user/test_router.exp")
    router_path = Path("/app/mock_router")
    audit_path = Path("/tmp/router_interaction_audit")

    assert script_path.exists(), f"Expect script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Expect script is not executable: {script_path}"
    first_line = script_path.read_text(errors="replace").splitlines()[0]
    assert first_line.startswith("#!") and "expect" in first_line.lower(), (
        "test_router.exp must be an Expect script with an Expect shebang"
    )

    try:
        proc = subprocess.run(
            [str(script_path)], capture_output=True, text=True, timeout=5
        )
        assert proc.returncode == 0, f"Expect script failed with return code {proc.returncode}\nStdout: {proc.stdout}\nStderr: {proc.stderr}"
    except subprocess.TimeoutExpired:
        pytest.fail("Expect script timed out, likely hanging on a prompt.")

    original_router = router_path.read_bytes()
    original_mode = stat.S_IMODE(router_path.stat().st_mode)
    instrumented_router = r'''#!/bin/bash
set -u
log=/tmp/router_interaction_audit
printf 'Username: '
IFS= read -r user || exit 21
printf 'USER:%s\n' "$user" >> "$log"
printf 'Password: '
IFS= read -r pass || exit 22
printf '\n'
printf 'PASS:%s\n' "$pass" >> "$log"
printf 'Router# '
IFS= read -r cmd || exit 23
printf 'CMD1:%s\n' "$cmd" >> "$log"
if [ "$cmd" = "show interface status" ]; then
    echo 'GigabitEthernet0/0/0  up      up'
fi
printf 'Router# '
IFS= read -r cmd || exit 24
printf 'CMD2:%s\n' "$cmd" >> "$log"
[ "$user" = admin ] && [ "$pass" = neteng_secret ] && [ "$cmd" = exit ]
'''

    try:
        if audit_path.exists():
            audit_path.unlink()
        router_path.write_text(instrumented_router)
        os.chmod(router_path, 0o755)
        try:
            proc = subprocess.run(
                [str(script_path)], capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Expect script timed out during the required router interaction")

        assert proc.returncode == 0, (
            f"Expect script failed instrumented interaction\nStdout: {proc.stdout}\nStderr: {proc.stderr}"
        )
        assert audit_path.exists(), "Expect script did not spawn /app/mock_router"
        audit = audit_path.read_text().splitlines()
        assert audit == [
            "USER:admin",
            "PASS:neteng_secret",
            "CMD1:show interface status",
            "CMD2:exit",
        ], f"Incorrect router interaction: {audit}"
        assert "GigabitEthernet0/0/0  up      up" in proc.stdout, (
            "Expect script did not capture the interface status output"
        )
    finally:
        router_path.write_bytes(original_router)
        os.chmod(router_path, original_mode)


def test_monitoring_cron():
    cron_path = "/home/user/monitoring_cron"
    assert os.path.exists(cron_path), f"Cron file missing: {cron_path}"

    with open(cron_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.startswith("#")]
    assert len(lines) > 0, "Cron file is empty or only contains comments"

    found_valid_cron = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 6:
            minute, hour, dom, month, dow = parts[:5]
            cmd = " ".join(parts[5:])
            if "/home/user/test_router.exp" in cmd:
                if minute == "*/5" or minute == "0,5,10,15,20,25,30,35,40,45,50,55":
                    found_valid_cron = True
                    break

    assert found_valid_cron, f"Did not find a valid cron entry for every 5 minutes running /home/user/test_router.exp in {cron_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
