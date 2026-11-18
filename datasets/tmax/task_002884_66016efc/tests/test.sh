#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess

DROPPER = "/home/user/dropper_build.sh"
MRE = "/home/user/mre.sh"


def read_script(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def active_text(content):
    return "\n".join(
        line for line in content.splitlines()
        if not line.lstrip().startswith("#")
    )


def bash_syntax_ok(path):
    result = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
    assert result.returncode == 0, f"{path} has invalid shell syntax: {result.stderr}"


def seeded_mods(seed, moduli):
    expressions = " ".join(f"$((RANDOM % {m}))" for m in moduli)
    command = f'RANDOM="$1"; printf "%s\\n" {expressions}'
    result = subprocess.run(
        ["bash", "-c", command, "_", str(seed)],
        capture_output=True,
        text=True,
        check=True,
    )
    return [int(x) for x in result.stdout.splitlines()]


def test_dropper_build_fixed():
    assert os.path.isfile(DROPPER), f"Script {DROPPER} is missing."
    bash_syntax_ok(DROPPER)

    # Avoid spending up to 100 seconds in the unchanged simulated sleep while
    # retaining the original assertion that 50 independent executions succeed.
    bindir = "/tmp/verifier-bin"
    os.makedirs(bindir, exist_ok=True)
    sleep_path = os.path.join(bindir, "sleep")
    with open(sleep_path, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nexit 0\n")
    os.chmod(sleep_path, 0o755)
    env = os.environ.copy()
    env["PATH"] = bindir + os.pathsep + env.get("PATH", "")

    for i in range(50):
        result = subprocess.run([DROPPER], capture_output=True, text=True, env=env, timeout=5)
        assert result.returncode == 0, (
            f"Script failed on run {i+1} with exit code {result.returncode}. "
            f"Stderr: {result.stderr}"
        )
        matches = re.findall(r"Payload size calculated:\s*(\d+)", result.stdout)
        assert len(matches) == 1, "The build must report exactly one calculated payload size."
        assert int(matches[0]) in {10000, 5000, 3333, 2500, 2000}, (
            f"Unexpected payload size {matches[0]}."
        )


def test_dropper_build_content_fix():
    content = read_script(DROPPER)
    active = active_text(content)

    # Keep the original checks.
    assert "PAYLOAD_SIZE=" in content, "PAYLOAD_SIZE assignment missing."
    assert "+ 1" in content or "+1" in content, (
        "The fix must add 1 to the random modulus result."
    )

    # Require the actual command, rather than accepting keywords in comments.
    fixed_assignment = re.compile(
        r"(?:^|[;\n])\s*PAYLOAD_SIZE\s*=\s*\$\(\(\s*"
        r"10000\s*/\s*\(\s*RANDOM\s*%\s*5\s*\+\s*1\s*\)\s*"
        r"\)\)(?=\s*(?:$|[;>&|]))",
        re.MULTILINE,
    )
    matches = list(fixed_assignment.finditer(active))
    assert len(matches) == 1, (
        "The active PAYLOAD_SIZE calculation must be exactly "
        "10000 / (RANDOM % 5 + 1)."
    )
    assignments = re.findall(r"(?:^|[;\n])\s*PAYLOAD_SIZE\s*=", active, re.MULTILINE)
    assert len(assignments) == 1, "There must be exactly one active PAYLOAD_SIZE assignment."

    # Source the real script with deterministic RANDOM seeds and compare its
    # reported result with values independently derived from bash's RANDOM stream.
    for seed in (1, 7, 19, 41, 83):
        sleep_mod, payload_mod = seeded_mods(seed, [3, 5])
        expected = 10000 // (payload_mod + 1)
        command = 'RANDOM="$1"; source "$2"'
        result = subprocess.run(
            ["bash", "-c", command, "_", str(seed), DROPPER],
            capture_output=True,
            text=True,
            env={**os.environ, "PATH": "/tmp/verifier-bin:" + os.environ.get("PATH", "")},
            timeout=5,
        )
        assert result.returncode == 0, f"Seeded build failed for seed {seed}: {result.stderr}"
        match = re.search(r"Payload size calculated:\s*(\d+)", result.stdout)
        assert match, "The executed build did not report its payload calculation."
        assert int(match.group(1)) == expected, (
            f"For seed {seed}, expected payload size {expected}, got {match.group(1)}."
        )


def test_mre_script_exists_and_executable():
    assert os.path.isfile(MRE), f"MRE script {MRE} does not exist."
    st = os.stat(MRE)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"MRE script {MRE} is not executable."
    bash_syntax_ok(MRE)


def test_mre_contains_buggy_arithmetic_in_loop():
    content = active_text(read_script(MRE))
    buggy_assignment = re.compile(
        r"(?:^|[;\n])\s*PAYLOAD_SIZE\s*=\s*\$\(\(\s*"
        r"10000\s*/\s*\(\s*RANDOM\s*%\s*5\s*\)\s*\)\)"
        r"(?=\s*(?:$|[;>&|]))",
        re.MULTILINE,
    )
    assert len(list(buggy_assignment.finditer(content))) == 1, (
        "MRE must contain the exact original buggy PAYLOAD_SIZE arithmetic evaluation."
    )

    loop_pattern = re.compile(
        r"\b(?:while|until|for|select)\b[\s\S]*?\bdo\b"
        r"(?P<body>[\s\S]*?)\bdone\b",
        re.MULTILINE,
    )
    assert any(buggy_assignment.search(m.group("body")) for m in loop_pattern.finditer(content)), (
        "The exact buggy arithmetic evaluation must be inside a loop."
    )


def test_mre_script_behavior():
    # Keep the original direct behavioral assertions.
    result = subprocess.run([MRE], capture_output=True, text=True, timeout=5)
    assert result.returncode == 1, f"MRE script exited with code {result.returncode}, expected 1."
    assert "division by 0" in result.stderr.lower(), (
        "Stderr did not contain 'division by 0' error."
    )
    assert result.stdout.strip() == "", "Standard output was not suppressed."


def test_mre_executes_the_real_loop_and_arithmetic():
    # Find a deterministic seed with several successful iterations followed by
    # zero, then use xtrace to prove that the assignment in the loop executes
    # with exactly the independently derived values before the real error.
    selected = None
    for seed in range(1, 300):
        mods = seeded_mods(seed, [5] * 40)
        if 0 in mods:
            zero_index = mods.index(0)
            if 3 <= zero_index < 20:
                selected = (seed, mods[:zero_index])
                break
    assert selected is not None, "Could not select a deterministic RANDOM seed."
    seed, nonzero_mods = selected
    expected_values = [10000 // value for value in nonzero_mods]

    result = subprocess.run(
        ["bash", "-x", "-c", 'RANDOM="$1"; source "$2"', "_", str(seed), MRE],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 1, "Seeded MRE did not exit with status 1 at the error."
    assert result.stdout.strip() == "", "Seeded MRE did not suppress standard output."
    traced_values = [
        int(value)
        for value in re.findall(r"^\++\s*PAYLOAD_SIZE=(\d+)\s*$", result.stderr, re.MULTILINE)
    ]
    assert traced_values == expected_values, (
        f"MRE did not execute the original arithmetic loop as expected: "
        f"expected {expected_values}, traced {traced_values}."
    )
    assert "division by 0" in result.stderr.lower(), "The real arithmetic error was not observed."
    assert re.search(r"10000\s*/\s*\(\s*RANDOM\s*%\s*5\s*\)", result.stderr), (
        "The division-by-zero diagnostic did not come from the original arithmetic expression."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
