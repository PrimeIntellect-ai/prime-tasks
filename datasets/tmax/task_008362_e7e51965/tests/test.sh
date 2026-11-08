#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pwd
import random
import re
import shutil
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "analyze.sh")
RESULTS = os.path.join(HOME, "results.txt")
USERS = os.path.join(HOME, "users.csv")
IMPRESSIONS = os.path.join(HOME, "impressions.csv")
CLICKS = os.path.join(HOME, "clicks.csv")
KEYS = ["N_A", "C_A", "P_A", "N_B", "C_B", "P_B", "Diff", "SE", "CI_Lower", "CI_Upper"]


def round_4(value):
    return Decimal(str(value)).quantize(Decimal("0.0000"), rounding=ROUND_HALF_UP)


def expected_from_files():
    for path in (USERS, IMPRESSIONS, CLICKS):
        assert os.path.isfile(path), f"Missing {path}"

    us_users = set()
    with open(USERS, encoding="utf-8") as f:
        f.readline()
        for line in f:
            parts = line.strip().split(",")
            if len(parts) >= 2 and parts[1] == "US":
                us_users.add(parts[0])

    impressions = {}
    with open(IMPRESSIONS, encoding="utf-8") as f:
        f.readline()
        for line in f:
            parts = line.strip().split(",")
            if len(parts) >= 2 and parts[0] in us_users:
                impressions[parts[0]] = parts[1]

    clicks = set()
    with open(CLICKS, encoding="utf-8") as f:
        f.readline()
        for line in f:
            parts = line.strip().split(",")
            if parts:
                clicks.add(parts[0])

    n_a = c_a = n_b = c_b = 0
    for uid, variant in impressions.items():
        if variant == "A":
            n_a += 1
            c_a += uid in clicks
        elif variant == "B":
            n_b += 1
            c_b += uid in clicks

    p_a = c_a / n_a if n_a else 0
    p_b = c_b / n_b if n_b else 0
    diff = p_a - p_b
    se = math.sqrt(p_a * (1 - p_a) / n_a + p_b * (1 - p_b) / n_b) if n_a and n_b else 0
    lower = diff - 1.96 * se
    upper = diff + 1.96 * se
    return {
        "N_A": str(n_a),
        "C_A": str(c_a),
        "P_A": f"{round_4(p_a):.4f}",
        "N_B": str(n_b),
        "C_B": str(c_b),
        "P_B": f"{round_4(p_b):.4f}",
        "Diff": f"{round_4(diff):.4f}",
        "SE": f"{round_4(se):.4f}",
        "CI_Lower": f"{round_4(lower):.4f}",
        "CI_Upper": f"{round_4(upper):.4f}",
    }


def make_allowed_path(directory):
    commands = [
        "bash", "awk", "gawk", "bc", "sed", "grep", "join", "sort",
        "cat", "cut", "paste", "comm", "head", "tail", "tr", "uniq",
        "wc", "printf", "echo", "test", "expr", "mktemp", "rm", "mv",
        "cp", "touch", "dirname", "basename", "date", "tee", "true",
        "false", "seq", "od", "fold", "nl"
    ]
    for command in commands:
        source = shutil.which(command)
        if source:
            destination = os.path.join(directory, command)
            if not os.path.lexists(destination):
                os.symlink(source, destination)


def run_script(allowed_path):
    if os.path.lexists(RESULTS):
        os.unlink(RESULTS)

    trace = tempfile.TemporaryFile(mode="w+b")
    env = {
        "PATH": allowed_path,
        "HOME": HOME,
        "LANG": "C",
        "LC_ALL": "C",
        "BASH_XTRACEFD": str(trace.fileno()),
        "PS4": "TRACE: ",
    }
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    completed = subprocess.run(
        ["/bin/bash", "--noprofile", "--norc", "-x", SCRIPT],
        cwd=HOME,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        pass_fds=(trace.fileno(),),
        preexec_fn=demote,
        timeout=20,
        text=True,
    )
    trace.seek(0)
    traced_commands = trace.read().decode("utf-8", "replace")
    trace.close()

    assert completed.returncode == 0, (
        f"analyze.sh exited with {completed.returncode}. stderr:\n{completed.stderr}"
    )
    assert "TRACE:" in traced_commands, "analyze.sh did not execute as a traced Bash workflow"
    assert not re.search(r"(?i)(?:^|[/'\"[:space:]])(?:python(?:[0-9.]*)?|perl|rscript)(?:$|[/'\"[:space:]])", traced_commands), (
        "analyze.sh invoked a prohibited language runtime"
    )
    assert os.path.isfile(RESULTS), f"Expected output file {RESULTS} does not exist after running analyze.sh"


def verify_results(expected):
    with open(RESULTS, "r", encoding="utf-8") as f:
        raw = f.read()

    lines = raw.splitlines()
    assert len(lines) == 10, f"results.txt must contain exactly 10 lines, found {len(lines)}"

    actual = {}
    for line in lines:
        assert ":" in line, f"Malformed output line: {line!r}"
        key, value = line.split(":", 1)
        actual[key.strip()] = value.strip()

    # Retain the original value assertions.
    for key, expected_value in expected.items():
        assert key in actual, f"Missing key '{key}' in {RESULTS}"
        if key in ("N_A", "C_A", "N_B", "C_B"):
            assert actual[key] == expected_value
        else:
            assert abs(float(actual[key]) - float(expected_value)) <= 0.0002

    # Enforce the instruction's exact order, labels, integer forms, and four decimals.
    expected_lines = [f"{key}: {expected[key]}" for key in KEYS]
    assert lines == expected_lines, (
        "results.txt must contain exactly the required lines in order with floating-point values formatted to four decimal places"
    )


def generated_fixture(seed):
    rng = random.Random(seed)
    ids = [str(50000 + i) for i in range(137)]
    users = []
    impressions = []
    clicks = []
    for index, uid in enumerate(ids):
        country = "US" if index % 4 != 0 else ("UK" if index % 2 else "CA")
        variant = "A" if (index * 7 + seed) % 11 < 6 else "B"
        users.append(f"{uid},{country},2024-02-{index % 28 + 1:02d}")
        impressions.append(f"{uid},{variant}")
        if (index * 13 + seed * 5) % (17 if variant == "A" else 11) < 3:
            clicks.append(f"{uid},2024-03-01T12:00:00Z")

    rng.shuffle(users)
    rng.shuffle(impressions)
    rng.shuffle(clicks)
    return (
        ("user_id,country,signup_date\n" + "\n".join(users) + "\n").encode(),
        ("user_id,variant\n" + "\n".join(impressions) + "\n").encode(),
        ("user_id,timestamp\n" + "\n".join(clicks) + "\n").encode(),
    )


def test_bash_script_and_results():
    assert os.path.isfile(SCRIPT), f"Expected Bash script {SCRIPT} does not exist"
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a submitted script, not a symbolic link"
    with open(SCRIPT, "rb") as f:
        script_data = f.read()
    assert script_data, "analyze.sh is empty"
    assert b"\x00" not in script_data, "analyze.sh is not a text Bash script"

    syntax = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"analyze.sh is not valid Bash syntax: {syntax.stderr}"

    paths = (USERS, IMPRESSIONS, CLICKS, RESULTS)
    originals = {}
    for path in paths:
        originals[path] = open(path, "rb").read() if os.path.isfile(path) else None

    allowed_dir = tempfile.mkdtemp(prefix="allowed-tools-")
    make_allowed_path(allowed_dir)
    try:
        # First retain the original verifier's recomputation against the shipped data.
        fixtures = [(originals[USERS], originals[IMPRESSIONS], originals[CLICKS])]
        # Then use unseen valid CSV inputs so fixed or precomputed results cannot pass.
        fixtures.extend(generated_fixture(seed) for seed in (31, 73, 109))

        for users_data, impressions_data, clicks_data in fixtures:
            for path, data in ((USERS, users_data), (IMPRESSIONS, impressions_data), (CLICKS, clicks_data)):
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, 0o666)
            expected = expected_from_files()
            run_script(allowed_dir)
            verify_results(expected)
    finally:
        shutil.rmtree(allowed_dir, ignore_errors=True)
        for path, data in originals.items():
            if data is None:
                if os.path.lexists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, 0o666 if path != SCRIPT else 0o755)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
