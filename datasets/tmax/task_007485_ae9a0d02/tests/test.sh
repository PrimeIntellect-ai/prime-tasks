#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess


def test_scripts_exist():
    scripts = [
        "/home/user/clean.sh",
        "/home/user/correlation.sh",
        "/home/user/ci.sh"
    ]
    for script in scripts:
        assert os.path.exists(script), f"Script {script} is missing."
        assert os.path.isfile(script), f"Script {script} is not a regular file."


def test_clean_data_csv():
    expected_content = """A,B,C,D
1,2.1,5.5,X
2,4.0,6.1,Y
3,6.2,5.9,Z
4,8.1,4.2,W
-1.5,-3.0,5.0,V
6,11.9,4.8,T
10,20.1,5.2,S"""
    assert os.path.exists("/home/user/clean_data.csv"), "/home/user/clean_data.csv is missing."
    with open("/home/user/clean_data.csv", "r") as f:
        content = f.read().strip()
    assert content == expected_content, "Content of /home/user/clean_data.csv is incorrect."


def test_cor_txt():
    assert os.path.exists("/home/user/cor.txt"), "/home/user/cor.txt is missing."
    with open("/home/user/cor.txt", "r") as f:
        content = f.read().strip()
    assert content == "0.9998", f"Expected correlation to be 0.9998, but got {content}"


def test_ci_txt():
    assert os.path.exists("/home/user/ci.txt"), "/home/user/ci.txt is missing."
    with open("/home/user/ci.txt", "r") as f:
        content = f.read().strip()
    assert content == "5.2429,4.8021,5.6837", f"Expected CI to be 5.2429,4.8021,5.6837, but got {content}"


def _run_script(path):
    result = subprocess.run(
        ["/bin/bash", path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"{path} failed: {result.stderr}"
    return result.stdout.strip()


def test_scripts_process_unseen_data():
    rng = secrets.SystemRandom()

    while True:
        a_values = rng.sample(range(-40, 41), 7)
        b_values = rng.sample(range(-60, 61), 7)
        mean_a = sum(a_values) / len(a_values)
        mean_b = sum(b_values) / len(b_values)
        covariance = sum((a - mean_a) * (b - mean_b) for a, b in zip(a_values, b_values)) / len(a_values)
        sd_a = math.sqrt(sum((a - mean_a) ** 2 for a in a_values) / len(a_values))
        sd_b = math.sqrt(sum((b - mean_b) ** 2 for b in b_values) / len(b_values))
        correlation = covariance / (sd_a * sd_b)
        if abs(correlation) > 0.05:
            break

    c_values = rng.sample(range(15, 76), 7)
    valid_entries = []
    for index, (a, b, c) in enumerate(zip(a_values, b_values, c_values)):
        valid_entries.append((f"{a},{b},{c},tag-{index}-{rng.randrange(10000, 99999)}", True))

    invalid_entries = [
        (f"not_numeric,{rng.randrange(1, 20)},{rng.randrange(1, 20)},badA", False),
        (f"{rng.randrange(1, 20)},bad,{rng.randrange(1, 20)},badB", False),
        (f"{rng.randrange(1, 20)},{rng.randrange(1, 20)},missing,badC", False),
        (f"{rng.randrange(1, 20)},{rng.randrange(1, 20)},{rng.randrange(1, 20)}", False),
        (f"{rng.randrange(1, 20)},{rng.randrange(1, 20)},{rng.randrange(1, 20)},too,many", False),
    ]
    entries = valid_entries + invalid_entries
    rng.shuffle(entries)

    raw_content = "A,B,C,D\n" + "\n".join(line for line, _ in entries) + "\n"
    expected_clean = "A,B,C,D\n" + "\n".join(line for line, valid in entries if valid)

    mean_c = sum(c_values) / len(c_values)
    sd_c = math.sqrt(sum((c - mean_c) ** 2 for c in c_values) / len(c_values))
    margin = 1.96 * sd_c / math.sqrt(len(c_values))
    expected_cor = f"{correlation:.4f}"
    expected_ci = f"{mean_c:.4f},{mean_c - margin:.4f},{mean_c + margin:.4f}"

    paths = [
        "/home/user/raw_data.csv",
        "/home/user/clean_data.csv",
        "/home/user/cor.txt",
        "/home/user/ci.txt",
    ]
    saved = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
        else:
            saved[path] = None

    try:
        with open("/home/user/raw_data.csv", "w") as f:
            f.write(raw_content)
        if os.path.exists("/home/user/clean_data.csv"):
            os.remove("/home/user/clean_data.csv")

        _run_script("/home/user/clean.sh")
        assert os.path.exists("/home/user/clean_data.csv"), "clean.sh did not create clean_data.csv"
        with open("/home/user/clean_data.csv", "r") as f:
            actual_clean = f.read().strip()
        assert actual_clean == expected_clean, "clean.sh did not correctly filter an unseen dataset"

        actual_cor = _run_script("/home/user/correlation.sh")
        assert actual_cor == expected_cor, f"correlation.sh returned {actual_cor}, expected {expected_cor}"

        actual_ci = _run_script("/home/user/ci.sh")
        assert actual_ci == expected_ci, f"ci.sh returned {actual_ci}, expected {expected_ci}"
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
