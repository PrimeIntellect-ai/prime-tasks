#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

PROCESS_RS = "/home/user/process.rs"
RESULT_CSV = "/home/user/result.csv"
USERS_CSV = "/home/user/users.csv"
SCORES_CSV = "/home/user/scores.csv"
BINARY = "/tmp/process_submission"

ORIGINAL_EXPECTED = (
    "username,final_score\n"
    "alice,56.12\n"
    "david,50.00\n"
    "charlie,20.00\n"
    "bob,6.93\n"
)


def read_result():
    assert os.path.isfile(RESULT_CSV), f"File missing: {RESULT_CSV}"
    with open(RESULT_CSV, "r", encoding="utf-8") as f:
        return f.read().strip().replace("\r\n", "\n")


def write_inputs(users, scores):
    with open(USERS_CSV, "w", encoding="utf-8", newline="") as f:
        f.write("user_id,username,multiplier\n")
        for user_id, username, multiplier in users:
            f.write(f"{user_id},{username},{multiplier}\n")

    score_text = "user_id,score1,score2,score3\n"
    for user_id, score1, score2, score3 in scores:
        score_text += f"{user_id},{score1},{score2},{score3}\n"
    with open(SCORES_CSV, "wb") as f:
        f.write(score_text.encode("utf-16le"))


def expected_result(users, scores):
    metadata = {user_id: (username, float(multiplier))
                for user_id, username, multiplier in users}
    rows = []
    for user_id, score1, score2, score3 in scores:
        if user_id in metadata:
            username, multiplier = metadata[user_id]
            value = math.sqrt(score1 ** 2 + score2 ** 2 + score3 ** 2) * multiplier
            rows.append((value, username))
    rows.sort(key=lambda row: row[0], reverse=True)
    return "username,final_score\n" + "".join(
        f"{username},{value:.2f}\n" for value, username in rows
    )


def run_and_check(users, scores, expected=None):
    write_inputs(users, scores)
    if os.path.exists(RESULT_CSV):
        os.remove(RESULT_CSV)
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=20)
    actual = read_result()
    wanted = (expected if expected is not None else expected_result(users, scores)).strip()
    assert actual == wanted, (
        f"Contents of {RESULT_CSV} do not match the expected output.\n"
        f"Expected:\n{wanted}\nActual:\n{actual}"
    )


def main():
    # Preserve the original final-state assertions.
    assert os.path.isfile(PROCESS_RS), f"File missing: {PROCESS_RS}"
    assert read_result() == ORIGINAL_EXPECTED.strip(), (
        f"Contents of {RESULT_CSV} do not match the original expected output."
    )

    # The submitted Rust source must compile into the artifact being tested.
    subprocess.run(
        ["rustc", PROCESS_RS, "-o", BINARY],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    original_users = [
        (1, "alice", "1.5"),
        (2, "bob", "0.8"),
        (3, "charlie", "2.0"),
        (4, "david", "0.5"),
    ]
    original_scores = [
        (1, 10, 20, 30),
        (2, 5, 5, 5),
        (3, 0, 10, 0),
        (4, 100, 0, 0),
    ]
    run_and_check(original_users, original_scores, ORIGINAL_EXPECTED)

    # Exercise decoding, joining, calculation, and sorting on unpredictable data.
    rng = random.SystemRandom()
    for case_number in range(3):
        while True:
            ids = rng.sample(range(100, 10000), 7)
            users = []
            scores = []
            values = []
            for index, user_id in enumerate(ids):
                multiplier_tenths = rng.randint(3, 30)
                multiplier = f"{multiplier_tenths / 10:.1f}"
                username = f"user_{case_number}_{index}_{rng.randrange(10**8, 10**9)}"
                triple = [rng.randint(0, 180) for _ in range(3)]
                if triple == [0, 0, 0]:
                    triple[0] = 1
                value = math.sqrt(sum(x * x for x in triple)) * (multiplier_tenths / 10)
                users.append((user_id, username, multiplier))
                scores.append((user_id, *triple))
                values.append(value)

            rounded = [f"{value:.2f}" for value in values]
            # Avoid ambiguous ties and exact half-cent rounding boundaries.
            safe_rounding = all(abs((value * 100) % 1 - 0.5) > 1e-7 for value in values)
            if len(set(rounded)) == len(rounded) and safe_rounding:
                break

        rng.shuffle(users)
        rng.shuffle(scores)
        run_and_check(users, scores)


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
