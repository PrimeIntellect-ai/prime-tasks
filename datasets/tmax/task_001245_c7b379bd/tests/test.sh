#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess


def test_bash_profile_exports():
    """Verify that the required environment variables are exported and source correctly."""
    bash_profile_path = "/home/user/.bash_profile"
    assert os.path.isfile(bash_profile_path), f"Missing {bash_profile_path}"

    with open(bash_profile_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "ZONE_A_BASE=14" in content, "ZONE_A_BASE is not correctly exported in .bash_profile"
    assert "ZONE_B_BASE=9" in content, "ZONE_B_BASE is not correctly exported in .bash_profile"
    assert "ZONE_C_BASE=18" in content, "ZONE_C_BASE is not correctly exported in .bash_profile"

    for name, value in (("ZONE_A_BASE", "14"), ("ZONE_B_BASE", "9"), ("ZONE_C_BASE", "18")):
        assert re.search(rf"(?m)^\s*export\s+{name}={value}\s*$", content), \
            f"Missing standard export statement for {name}"

    command = (
        "source /home/user/.bash_profile && "
        "printf '%s,%s,%s' \"$ZONE_A_BASE\" \"$ZONE_B_BASE\" \"$ZONE_C_BASE\""
    )
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", command],
        env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": "/home/user"},
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "14,9,18"


def run_setup(script_path):
    return subprocess.run(
        ["bash", script_path],
        env={**os.environ, "HOME": "/home/user"},
        capture_output=True,
        text=True,
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_setup_proxy_script():
    """Verify setup_proxy.sh sources the profile and creates the exact rules file."""
    script_path = "/home/user/setup_proxy.sh"
    rules_path = "/home/user/firewall_rules.txt"
    profile_path = "/home/user/.bash_profile"

    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    if os.path.exists(rules_path):
        os.remove(rules_path)

    result = run_setup(script_path)
    assert result.returncode == 0, f"setup_proxy.sh failed to execute: {result.stderr}"
    assert os.path.isfile(rules_path), f"{rules_path} was not created by setup_proxy.sh"

    expected_lines = [
        "FORWARD PORT 80 TO ZONE A COST 14",
        "FORWARD PORT 80 TO ZONE B COST 9",
        "FORWARD PORT 80 TO ZONE C COST 18",
    ]
    assert read_nonempty_lines(rules_path) == expected_lines, \
        f"Content of {rules_path} does not match expected output"

    # Change the sourced values temporarily so hardcoded firewall output cannot pass.
    with open(profile_path, "rb") as f:
        original_profile = f.read()
    try:
        with open(profile_path, "ab") as f:
            f.write(b"\nexport ZONE_A_BASE=31\nexport ZONE_B_BASE=-7\nexport ZONE_C_BASE=42\n")
        os.remove(rules_path)
        result = run_setup(script_path)
        assert result.returncode == 0, f"setup_proxy.sh failed with changed profile: {result.stderr}"
        assert read_nonempty_lines(rules_path) == [
            "FORWARD PORT 80 TO ZONE A COST 31",
            "FORWARD PORT 80 TO ZONE B COST -7",
            "FORWARD PORT 80 TO ZONE C COST 42",
        ], "setup_proxy.sh must source .bash_profile and expand its zone variables"
    finally:
        with open(profile_path, "wb") as f:
            f.write(original_profile)


def expected_route(req_id, size_mb, za, zb, zc):
    costs = [
        ("ZONE_A", za * size_mb + req_id % 3),
        ("ZONE_B", zb * size_mb + req_id % 5),
        ("ZONE_C", zc * size_mb + req_id % 2),
    ]
    return min(costs, key=lambda item: item[1])[0]


def run_agent(script, request, bases):
    env = os.environ.copy()
    env.update({
        "ZONE_A_BASE": str(bases[0]),
        "ZONE_B_BASE": str(bases[1]),
        "ZONE_C_BASE": str(bases[2]),
    })
    return subprocess.run(
        ["python3", script, json.dumps(request, separators=(",", ":"))],
        env=env,
        capture_output=True,
        text=True,
        timeout=5,
    )


def assert_valid_decision(script, req_id, size_mb, bases):
    result = run_agent(script, {"req_id": req_id, "size_mb": size_mb}, bases)
    assert result.returncode == 0, \
        f"Agent failed for req_id={req_id}, size_mb={size_mb}, bases={bases}: {result.stderr}"
    expected = f"ROUTE_TO: {expected_route(req_id, size_mb, *bases)}"
    assert result.stderr == "", f"Agent wrote unexpected stderr: {result.stderr!r}"
    assert result.stdout.strip() == expected, \
        f"Expected {expected!r}, got {result.stdout!r} for bases={bases}"
    assert len(result.stdout.strip().splitlines()) == 1, "Agent must print only one routing decision"


def test_lb_proxy_formula_environment_and_ties():
    """Exercise every zone, environment reads, formulas, and specified tie ordering."""
    script = "/home/user/lb_proxy.py"
    assert os.path.isfile(script), f"Missing {script}"

    cases = [
        (1, 2, (1, 10, 10)),       # A uniquely cheapest
        (1, 2, (10, 1, 10)),       # B uniquely cheapest
        (1, 2, (10, 10, 1)),       # C uniquely cheapest
        (0, 0, (10, 10, 10)),      # three-way tie: A
        (0, 1, (1, 1, 100)),       # A/B tie: A
        (0, 1, (100, 1, 1)),       # B/C tie: B
        (-17, -4, (14, 9, 18)),     # negative integers exercise full formulas
        (12345, 0, (14, 9, 18)),
    ]
    for req_id, size_mb, bases in cases:
        assert_valid_decision(script, req_id, size_mb, bases)

    rng = random.SystemRandom()
    for _ in range(500):
        req_id = rng.randint(-100000, 100000)
        size_mb = rng.randint(-1000, 1000)
        bases = tuple(rng.randint(-50, 50) for _ in range(3))
        assert_valid_decision(script, req_id, size_mb, bases)


def test_lb_proxy_requires_exactly_one_valid_argument():
    script = "/home/user/lb_proxy.py"
    env = os.environ.copy()
    env.update({"ZONE_A_BASE": "14", "ZONE_B_BASE": "9", "ZONE_C_BASE": "18"})
    invalid_argv = [
        ["python3", script],
        ["python3", script, '{}', '{}'],
        ["python3", script, "not-json"],
        ["python3", script, '{}'],
        ["python3", script, '{"req_id":1}'],
    ]
    for argv in invalid_argv:
        result = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=5)
        assert "ROUTE_TO:" not in result.stdout, \
            f"Invalid invocation must not produce a routing decision: {argv}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
