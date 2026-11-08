#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

SCRIPT_PATH = "/home/user/find_match.sh"
USERS_PATH = "/home/user/users.csv"
CANDIDATES_PATH = "/home/user/candidates.csv"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"


def test_find_match_u100():
    result = subprocess.run(
        ["bash", SCRIPT_PATH, "U100"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    output = result.stdout.strip()
    assert output == "C4", f"Expected output 'C4' for U100, but got '{output}'"


def test_find_match_u102():
    result = subprocess.run(
        ["bash", SCRIPT_PATH, "U102"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    output = result.stdout.strip()
    assert output == "C5", f"Expected output 'C5' for U102, but got '{output}'"


def test_find_match_u101():
    result = subprocess.run(
        ["bash", SCRIPT_PATH, "U101"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    output = result.stdout.strip()
    assert output == "C4", f"Expected output 'C4' for U101, but got '{output}'"


def run_and_check(user_id, expected):
    result = subprocess.run(
        ["bash", SCRIPT_PATH, user_id],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    assert result.stdout in (expected, expected + "\n"), (
        f"Expected only {expected!r} on stdout, got {result.stdout!r}"
    )


def write_data(users, candidates):
    with open(USERS_PATH, "w", encoding="utf-8", newline="") as f:
        f.write("id,age,score1,score2\n")
        for row in users:
            f.write(",".join(map(str, row)) + "\n")
    with open(CANDIDATES_PATH, "w", encoding="utf-8", newline="") as f:
        f.write("cand_id,age,score1,score2\n")
        for row in candidates:
            f.write(",".join(map(str, row)) + "\n")


def token(prefix):
    return prefix + secrets.token_hex(8)


def test_computes_matches_from_current_csv_contents():
    original_users = open(USERS_PATH, "rb").read()
    original_candidates = open(CANDIDATES_PATH, "rb").read()
    rng = random.SystemRandom()

    try:
        # This case specifically changes the winner when score1 is not scaled by 10.
        uid = token("U")
        expected = token("C")
        unscaled_winner = token("C")
        far = token("C")
        users = [
            (token("U"), 70, "0.0", "0.0"),
            (uid, 30, "0.5", "0.2"),
            (token("U"), 10, "1.0", "1.0"),
        ]
        candidates = [
            (unscaled_winner, 30, "0.7", "0.2"),
            (far, 80, "0.0", "1.0"),
            (expected, 31, "0.5", "0.2"),
        ]
        rng.shuffle(users)
        rng.shuffle(candidates)
        write_data(users, candidates)
        run_and_check(uid, expected)

        # Exercise fresh, unpredictable IDs, row orders, values, and file sizes.
        # Distances are computed independently as exact integer multiples of 0.01.
        for _ in range(12):
            uid = token("U")
            user_age = rng.randint(18, 75)
            user_s1 = rng.randint(0, 10)
            user_s2 = rng.randint(0, 10)
            users = [(uid, user_age, f"{user_s1}/10", f"{user_s2}/10")]
            # CSV fields must be decimal numbers, so replace the temporary fractions.
            users = [(u, a, f"{s1 / 10:.1f}", f"{s2 / 10:.1f}")
                     for (u, a, s1, s2) in [(uid, user_age, user_s1, user_s2)]]
            for _decoy in range(rng.randint(1, 4)):
                users.append((token("U"), rng.randint(18, 75),
                              f"{rng.randint(0, 10) / 10:.1f}",
                              f"{rng.randint(0, 10) / 10:.1f}"))

            while True:
                candidates = []
                distances = []
                for _candidate in range(rng.randint(5, 10)):
                    cid = token("C")
                    age = rng.randint(18, 75)
                    s1 = rng.randint(0, 10)
                    s2 = rng.randint(0, 10)
                    candidates.append((cid, age, f"{s1 / 10:.1f}", f"{s2 / 10:.1f}"))
                    # 100 times the required squared distance.
                    distance = (100 * (age - user_age) ** 2
                                + 100 * (s1 - user_s1) ** 2
                                + (s2 - user_s2) ** 2)
                    distances.append(distance)
                minimum = min(distances)
                if distances.count(minimum) == 1:
                    expected = candidates[distances.index(minimum)][0]
                    break

            rng.shuffle(users)
            rng.shuffle(candidates)
            write_data(users, candidates)
            run_and_check(uid, expected)
    finally:
        with open(USERS_PATH, "wb") as f:
            f.write(original_users)
        with open(CANDIDATES_PATH, "wb") as f:
            f.write(original_candidates)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
