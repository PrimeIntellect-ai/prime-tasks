#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_recommender"
AGENT_PATH = "/home/user/recommender.sh"
NUM_ITERATIONS = 20


def generate_fuzz_inputs(seed):
    rng = random.Random(seed)
    num_items = rng.randint(50, 100)
    item_ids = rng.sample(range(1, 201), num_items)
    items_lines = [f"{iid},{rng.randint(1, 50)},{rng.randint(1, 50)}\n" for iid in item_ids]

    num_ratings = rng.randint(200, 500)
    user_ids = range(1, 21)
    possible_pairs = [(u, i) for u in user_ids for i in item_ids]
    selected_pairs = rng.sample(possible_pairs, min(num_ratings, len(possible_pairs)))
    ratings_lines = [f"{u},{i},{rng.randint(1, 5)}\n" for u, i in selected_pairs]
    return "".join(ratings_lines), "".join(items_lines)


def reference_output(ratings_csv, items_csv):
    items = {}
    for line in items_csv.splitlines():
        if line:
            iid, f1, f2 = map(int, line.split(','))
            items[iid] = (f1, f2)

    profiles = {}
    rated = {}
    for line in ratings_csv.splitlines():
        if not line:
            continue
        uid, iid, rating = map(int, line.split(','))
        rated.setdefault(uid, set()).add(iid)
        if iid in items:
            p1, p2 = profiles.get(uid, (0, 0))
            f1, f2 = items[iid]
            profiles[uid] = (p1 + f1 * rating, p2 + f2 * rating)

    output = []
    for uid in sorted(profiles):
        uf1, uf2 = profiles[uid]
        best_item = None
        best_score = -1
        for iid in sorted(items):
            if iid in rated.get(uid, set()):
                continue
            f1, f2 = items[iid]
            score = uf1 * f1 + uf2 * f2
            if score > best_score:
                best_score = score
                best_item = iid
        if best_item is not None:
            output.append(f"{uid},{best_item}\n")
    return "".join(output)


def assert_readable_shell_implementation():
    st = os.lstat(AGENT_PATH)
    assert stat.S_ISREG(st.st_mode), "Submission must be a regular script"
    assert not stat.S_ISLNK(st.st_mode), "Submission must not be a symlink"

    raw = open(AGENT_PATH, "rb").read()
    assert raw and b"\x00" not in raw, "Submission must be readable shell source, not a binary"
    assert len(raw) <= 100000, "Submission is unexpectedly large for a Bash/AWK implementation"
    source = raw.decode("utf-8")

    syntax = subprocess.run(["bash", "-n", AGENT_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"
    assert not re.search(r"legacy_recommender|/app/", source, re.I), \
        "The replacement must not invoke or reference the legacy executable"

    substantive = [line for line in source.splitlines()
                   if line.strip() and not line.lstrip().startswith('#')]
    assert len(substantive) >= 5 and len(source) >= 150, \
        "Submission must contain a readable implementation, not a delegation wrapper"
    assert re.search(r"\bawk\b|\b(for|while)\b", source), \
        "Submission must implement the processing logic in Bash/AWK"

    # A copied native executable is also delegation, even if given another name.
    for root in ("/home/user", "/tmp", "/var/tmp", "/dev/shm"):
        if not os.path.isdir(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            for name in filenames:
                path = os.path.join(dirpath, name)
                if path == AGENT_PATH:
                    continue
                try:
                    fst = os.stat(path, follow_symlinks=False)
                    if fst.st_uid == st.st_uid:
                        with open(path, "rb") as f:
                            assert f.read(4) != b"\x7fELF", \
                                f"Native helper executable is not allowed: {path}"
                except (OSError, PermissionError):
                    pass


def run_agent(ratings_csv, items_csv):
    tmpdir = tempfile.mkdtemp(prefix="recommender-test-")
    os.chmod(tmpdir, 0o755)
    ratings_path = os.path.join(tmpdir, "ratings.csv")
    items_path = os.path.join(tmpdir, "items.csv")
    with open(ratings_path, "w") as f:
        f.write(ratings_csv)
    with open(items_path, "w") as f:
        f.write(items_csv)
    os.chmod(ratings_path, 0o644)
    os.chmod(items_path, 0o644)
    try:
        return subprocess.run(
            ["runuser", "-u", "user", "--", "bash", AGENT_PATH, ratings_path, items_path],
            capture_output=True, text=True, timeout=15
        )
    finally:
        for path in (ratings_path, items_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        os.rmdir(tmpdir)


def test_fuzz_equivalence_and_independent_implementation():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing: {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent script missing: {AGENT_PATH}"
    assert_readable_shell_implementation()

    cases = [generate_fuzz_inputs(42 + i) for i in range(NUM_ITERATIONS)]
    cases.extend([
        ("1,1,5\n1,2,1\n", "1,2,3\n2,4,1\n"),
        ("2,99,5\n3,1,2\n", "1,1,1\n2,1,1\n3,2,5\n"),
        ("10,5,3\n10,7,2\n11,5,1\n", "9,8,1\n5,2,4\n7,6,3\n3,7,7\n"),
    ])

    expected = []
    for i, (ratings_csv, items_csv) in enumerate(cases):
        with tempfile.TemporaryDirectory() as tmpdir:
            ratings_path = os.path.join(tmpdir, "ratings.csv")
            items_path = os.path.join(tmpdir, "items.csv")
            open(ratings_path, "w").write(ratings_csv)
            open(items_path, "w").write(items_csv)
            oracle_proc = subprocess.run(
                [ORACLE_PATH, ratings_path, items_path], capture_output=True, text=True
            )
            assert oracle_proc.returncode == 0, \
                f"Oracle failed on iteration {i}. Stderr: {oracle_proc.stderr}"
            derived = reference_output(ratings_csv, items_csv)
            assert oracle_proc.stdout == derived, "Independent reference disagrees with oracle"
            expected.append(derived)

    # Hide the black-box while submissions execute, so wrappers cannot pass the
    # behavioral tests by delegating to it.
    hidden_dir = tempfile.mkdtemp(prefix="recommender-oracle-", dir="/root")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle")
    os.rename(ORACLE_PATH, hidden_oracle)
    try:
        for i, ((ratings_csv, items_csv), wanted) in enumerate(zip(cases, expected)):
            agent_proc = run_agent(ratings_csv, items_csv)
            assert agent_proc.returncode == 0, \
                f"Agent failed on iteration {i}. Stderr: {agent_proc.stderr}"
            if agent_proc.stdout != wanted:
                pytest.fail(
                    f"Mismatch on iteration {i}.\n"
                    f"ratings.csv ({len(ratings_csv.splitlines())} lines)\n"
                    f"items.csv ({len(items_csv.splitlines())} lines)\n\n"
                    f"Expected stdout:\n{wanted}\n"
                    f"Agent stdout:\n{agent_proc.stdout}\n"
                    f"Agent stderr:\n{agent_proc.stderr}\n"
                )
    finally:
        os.rename(hidden_oracle, ORACLE_PATH)
        os.rmdir(hidden_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
