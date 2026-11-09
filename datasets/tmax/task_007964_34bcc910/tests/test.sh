#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/build_acl.sh"
OUTPUT_PATH = "/home/user/final_acl.txt"


def run_script(team_a_lines, team_b_lines, constraint_lines):
    with tempfile.TemporaryDirectory() as tmpdir:
        team_a_path = os.path.join(tmpdir, "team_a.txt")
        team_b_path = os.path.join(tmpdir, "team_b.txt")
        constraints_path = os.path.join(tmpdir, "constraints.txt")

        for path, lines in (
            (team_a_path, team_a_lines),
            (team_b_path, team_b_lines),
            (constraints_path, constraint_lines),
        ):
            with open(path, "w") as f:
                f.write("\n".join(lines))
                if lines:
                    f.write("\n")

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            [SCRIPT_PATH, team_a_path, team_b_path, constraints_path],
            capture_output=True,
            text=True,
            timeout=10,
        )

        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}.\n"
            f"Stderr: {result.stderr}"
        )
        assert os.path.exists(OUTPUT_PATH), (
            f"Output file {OUTPUT_PATH} was not created by the script"
        )
        assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a regular file"

        with open(OUTPUT_PATH, "r") as f:
            return [line.strip() for line in f if line.strip()]


def expected_output(team_a_lines, team_b_lines, constraint_lines):
    deny_prefixes = [line.split(" ", 1)[1] for line in constraint_lines]
    merged = set(team_a_lines + team_b_lines)
    return sorted(
        line
        for line in merged
        if not any(line.split(" ", 1)[1].startswith(prefix) for prefix in deny_prefixes)
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_original_script_logic():
    team_a = [
        "ALLOW /api/v1/users",
        "ALLOW /public/home",
        "ALLOW /admin/settings",
        "ALLOW /shared/data",
    ]
    team_b = [
        "ALLOW /public/home",
        "ALLOW /internal/stats",
        "ALLOW /api/v2/users",
        "ALLOW /shared/data",
    ]
    constraints = ["DENY /admin", "DENY /internal"]

    output_lines = run_script(team_a, team_b, constraints)
    expected_lines = [
        "ALLOW /api/v1/users",
        "ALLOW /api/v2/users",
        "ALLOW /public/home",
        "ALLOW /shared/data",
    ]
    assert output_lines == expected_lines, (
        f"Output file contents do not match expected.\n"
        f"Expected: {expected_lines}\nGot: {output_lines}"
    )


def test_runtime_generated_inputs():
    rng = secrets.SystemRandom()

    for _ in range(6):
        root = secrets.token_hex(10)
        blocked = secrets.token_hex(6)
        exact = secrets.token_hex(6)
        suffix = secrets.token_hex(5)

        paths = [
            f"/{root}/zeta/{secrets.token_hex(4)}",
            f"/{root}/alpha/{secrets.token_hex(4)}",
            f"/{root}/{blocked}",
            f"/{root}/{blocked}/child/{secrets.token_hex(3)}",
            f"/{root}/{blocked}{suffix}",
            f"/{root}/other/{secrets.token_hex(4)}",
            f"/{root}/{exact}",
            f"/{root}/team-b-only/{secrets.token_hex(3)}",
        ]

        team_a = [f"ALLOW {path}" for path in paths[:7]]
        team_b = [
            f"ALLOW {paths[1]}",
            f"ALLOW {paths[3]}",
            f"ALLOW {paths[5]}",
            f"ALLOW {paths[7]}",
        ]
        rng.shuffle(team_a)
        rng.shuffle(team_b)

        constraints = [
            f"DENY /{root}/{blocked}",
            f"DENY /{root}/{exact}",
            f"DENY /{root}/does-not-exist-{secrets.token_hex(3)}",
        ]
        rng.shuffle(constraints)

        actual = run_script(team_a, team_b, constraints)
        expected = expected_output(team_a, team_b, constraints)
        assert actual == expected, (
            "Script failed on runtime-generated ACL inputs.\n"
            f"Expected: {expected}\nGot: {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
