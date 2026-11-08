#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

ORACLE_ORIGINAL=/app/legacy_scorer
ORACLE_DIR="$(mktemp -d /tmp/verifier-oracle.XXXXXX)"
ORACLE_PRIVATE="$ORACLE_DIR/legacy_scorer"
chmod 700 "$ORACLE_DIR"

restore_oracle() {
    if [ -f "$ORACLE_PRIVATE" ]; then
        mv "$ORACLE_PRIVATE" "$ORACLE_ORIGINAL"
    fi
    rm -rf "$ORACLE_DIR"
}
trap restore_oracle EXIT

if [ ! -f "$ORACLE_ORIGINAL" ] || [ ! -x "$ORACLE_ORIGINAL" ]; then
    exit 0
fi
mv "$ORACLE_ORIGINAL" "$ORACLE_PRIVATE"
export ORACLE_PRIVATE

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import string
import subprocess
import tempfile

import pytest

ORACLE_PATH = os.environ["ORACLE_PRIVATE"]
AGENT_SCRIPT = "/home/user/scorer.sh"
NUM_ITERATIONS = 50
USER = pwd.getpwnam("user")
FORBIDDEN_TRACE = re.compile(
    r"(^|[\\s/])(?:legacy_scorer|python(?:[0-9.]+)?|perl|ruby|node(?:js)?|php|lua|Rscript|gcc|cc|clang)(?=$|[\\s;|&<>/])",
    re.IGNORECASE,
)


def generate_random_csv(file_path, num_rows):
    with open(file_path, "w") as f:
        for _ in range(num_rows):
            artifact_id = "".join(random.choices(string.ascii_letters + string.digits, k=8))
            metric_a = f"{random.uniform(0.01, 0.99):.4f}"
            metric_b = f"{random.uniform(0.01, 0.99):.4f}"
            metric_c = f"{random.uniform(0.01, 0.99):.4f}"
            f.write(f"{artifact_id},{metric_a},{metric_b},{metric_c}\n")


def derived_output(csv_path, prior):
    p = float(prior)
    lines = []
    with open(csv_path) as f:
        for line in f:
            fields = line.rstrip("\n").split(",")
            if len(fields) != 4:
                continue
            artifact_id, a, b, c = fields
            s = 0.40 * float(a) + 0.35 * float(b) + 0.25 * float(c)
            posterior = (s * p) / ((s * p) + ((1.0 - s) * (1.0 - p)))
            lines.append(f"{artifact_id},{posterior:.6f}\n")
    return "".join(lines)


def demote():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def agent_environment():
    env = os.environ.copy()
    env.pop("ORACLE_PRIVATE", None)
    env["HOME"] = USER.pw_dir
    return env


def run_agent(prior, csv_path, direct=False):
    if direct:
        cmd = [AGENT_SCRIPT, "--prior", prior, csv_path]
    else:
        # Preserve the original verifier's explicit Bash execution while enabling
        # xtrace so prohibited interpreters and compilers actually invoked are seen.
        cmd = ["/bin/bash", "-x", AGENT_SCRIPT, "--prior", prior, csv_path]
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=USER.pw_dir,
        env=agent_environment(),
        preexec_fn=demote,
        timeout=20,
    )
    if not direct:
        assert not FORBIDDEN_TRACE.search(result.stderr), (
            "The scorer invoked the legacy tool, a higher-level interpreter, "
            f"or a compiler. Trace:\n{result.stderr}"
        )
    return result


def find_user_elf_helpers():
    findings = []
    roots = ["/home/user", "/tmp", "/var/tmp", "/dev/shm"]
    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(current, d))]
            for name in files:
                path = os.path.join(current, name)
                if path == AGENT_SCRIPT or path.startswith(os.path.dirname(ORACLE_PATH) + os.sep):
                    continue
                try:
                    st = os.lstat(path)
                    if root != "/home/user" and st.st_uid != USER.pw_uid:
                        continue
                    if os.path.islink(path):
                        target = os.path.realpath(path)
                        base = os.path.basename(target).lower()
                        if re.fullmatch(r"python(?:[0-9.]+)?|perl|ruby|node(?:js)?|php|lua|rscript", base):
                            findings.append(path)
                        continue
                    with open(path, "rb") as f:
                        if f.read(4) == b"\x7fELF":
                            findings.append(path)
                except (OSError, PermissionError):
                    continue
    return findings


@pytest.fixture(scope="session", autouse=True)
def reject_compiled_helpers():
    assert not find_user_elf_helpers(), "Compiled helper found in an agent-writable location"
    yield
    findings = find_user_elf_helpers()
    assert not findings, f"Compiled helper(s) found: {findings}"


def test_scorer_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"The script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"{AGENT_SCRIPT} is not executable."
    with open(AGENT_SCRIPT, "rb") as f:
        beginning = f.read(256)
    assert not beginning.startswith(b"\x7fELF"), "scorer.sh must be a Bash script, not a compiled program"
    assert b"\x00" not in beginning, "scorer.sh must be a text Bash script"
    first_line = beginning.splitlines()[0] if beginning.splitlines() else b""
    assert first_line.startswith(b"#!") and b"bash" in first_line, "scorer.sh must have a Bash shebang"


def test_direct_drop_in_execution():
    prior = "0.370"
    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".csv") as tmp:
        tmp.write("directA,0.1250,0.5000,0.8750\n")
        tmp.write("directB,0.9100,0.2300,0.4400\n")
        csv_path = tmp.name
    os.chmod(csv_path, 0o644)
    try:
        result = run_agent(prior, csv_path, direct=True)
        assert result.returncode == 0, result.stderr
        assert result.stdout == derived_output(csv_path, prior)
    finally:
        os.remove(csv_path)


def test_scorer_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    random.seed(42)

    for i in range(NUM_ITERATIONS):
        prior = f"{random.uniform(0.100, 0.900):.3f}"
        num_rows = random.randint(10, 50)

        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".csv") as tmp:
            csv_path = tmp.name
        os.chmod(csv_path, 0o644)

        try:
            generate_random_csv(csv_path, num_rows)
            os.chmod(csv_path, 0o644)

            oracle_cmd = [ORACLE_PATH, "--prior", prior, csv_path]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i} with error: {oracle_res.stderr}"
            oracle_output = oracle_res.stdout

            expected_output = derived_output(csv_path, prior)
            assert oracle_output == expected_output, "Derived expectation disagrees with the oracle"

            agent_res = run_agent(prior, csv_path)
            assert agent_res.returncode == 0, f"Agent script failed on iteration {i} with error: {agent_res.stderr}"
            agent_output = agent_res.stdout

            if oracle_output != agent_output:
                with open(csv_path, "r") as f:
                    input_data = f.read()
                pytest.fail(
                    f"Mismatch on iteration {i}.\n"
                    f"Prior: {prior}\n"
                    f"Input CSV:\n{input_data}\n"
                    f"Oracle Output:\n{oracle_output}\n"
                    f"Agent Output:\n{agent_output}"
                )
        finally:
            if os.path.exists(csv_path):
                os.remove(csv_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
