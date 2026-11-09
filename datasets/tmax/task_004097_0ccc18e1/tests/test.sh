#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")
PROJECT = HOME / "etl_pipeline"
CLICKS = HOME / "clicks.csv"
OUTPUT = HOME / "output.json"
STATUS = HOME / "repro_status.txt"
SCRIPT = HOME / "test_reproducibility.sh"


def test_output_json_exists_and_correct():
    """Test that output.json exists and contains the correct data."""
    output_path = "/home/user/output.json"
    assert os.path.exists(output_path), f"File {output_path} does not exist."

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    assert "user_profiles" in data, "Key 'user_profiles' missing from output.json"
    assert "item_similarities" in data, "Key 'item_similarities' missing from output.json"

    expected_profiles = [
        {"user_id": "u1", "category": "A", "alpha": 2, "beta": 2},
        {"user_id": "u2", "category": "A", "alpha": 2, "beta": 1},
        {"user_id": "u2", "category": "B", "alpha": 2, "beta": 1},
        {"user_id": "u3", "category": "B", "alpha": 3, "beta": 1}
    ]

    expected_similarities = [
        {"item_1": "i1", "item_2": "i2", "jaccard": 0.3333},
        {"item_1": "i1", "item_2": "i3", "jaccard": 0.0},
        {"item_1": "i2", "item_2": "i3", "jaccard": 0.5}
    ]

    assert data["user_profiles"] == expected_profiles, "user_profiles do not match expected values or sorting."
    assert data["item_similarities"] == expected_similarities, "item_similarities do not match expected values or sorting."


def test_reproducibility_script_exists():
    """Test that the reproducibility bash script was created."""
    script_path = "/home/user/test_reproducibility.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."


def test_repro_status_correct():
    """Test that repro_status.txt contains the correct output."""
    status_path = "/home/user/repro_status.txt"
    assert os.path.exists(status_path), f"File {status_path} does not exist."

    with open(status_path, "r") as f:
        content = f.read().strip()

    assert content == "REPRODUCIBLE", f"Expected 'REPRODUCIBLE' in {status_path}, got '{content}'"


def expected_for(rows):
    profiles = {}
    items = set()
    clicked_users = {}

    for user_id, item_id, category, clicked_text in rows:
        clicked = int(clicked_text)
        items.add(item_id)
        alpha, beta = profiles.get((user_id, category), (1, 1))
        if clicked == 1:
            alpha += 1
            clicked_users.setdefault(item_id, set()).add(user_id)
        else:
            beta += 1
        profiles[(user_id, category)] = (alpha, beta)

    user_profiles = [
        {"user_id": user, "category": category, "alpha": values[0], "beta": values[1]}
        for (user, category), values in sorted(profiles.items())
    ]

    item_similarities = []
    sorted_items = sorted(items)
    for index, item_1 in enumerate(sorted_items):
        for item_2 in sorted_items[index + 1:]:
            users_1 = clicked_users.get(item_1, set())
            users_2 = clicked_users.get(item_2, set())
            union = users_1 | users_2
            value = 0.0 if not union else round(len(users_1 & users_2) / len(union), 4)
            item_similarities.append({
                "item_1": item_1,
                "item_2": item_2,
                "jaccard": value,
            })

    return {
        "user_profiles": user_profiles,
        "item_similarities": item_similarities,
    }


def write_clicks(rows):
    with CLICKS.open("w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["user_id", "item_id", "category", "clicked"])
        writer.writerows(rows)


def run_pipeline():
    assert PROJECT.is_dir(), f"Rust project directory {PROJECT} does not exist"
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing"
    assert (PROJECT / "src" / "main.rs").is_file(), "Rust src/main.rs is missing"
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml")],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust pipeline failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert OUTPUT.is_file(), "Running the Rust pipeline did not create output.json"
    try:
        return json.loads(OUTPUT.read_text()), OUTPUT.read_bytes()
    except json.JSONDecodeError as exc:
        pytest.fail(f"Rust pipeline produced invalid JSON: {exc}")


def test_z_rust_pipeline_and_reproducibility_are_executed():
    token = secrets.token_hex(6)
    users = [f"u_{n}_{token}" for n in range(1, 5)]
    items = [f"i_{n}_{token}" for n in range(1, 5)]
    categories = [f"cat_{n}_{token}" for n in range(1, 4)]
    rows = [
        (users[0], items[0], categories[0], "1"),
        (users[0], items[1], categories[0], "0"),
        (users[0], items[1], categories[1], "1"),
        (users[1], items[0], categories[0], "1"),
        (users[1], items[0], categories[0], "1"),
        (users[1], items[2], categories[1], "0"),
        (users[2], items[1], categories[1], "1"),
        (users[2], items[2], categories[1], "1"),
        (users[3], items[3], categories[2], "0"),
    ]
    expected = expected_for(rows)

    tracked = [CLICKS, OUTPUT, STATUS, HOME / "out1.json", HOME / "out2.json"]
    saved = {path: path.read_bytes() if path.exists() and path.is_file() else None for path in tracked}

    try:
        # Execute the submitted Cargo project on data unknown when the agent ran.
        write_clicks(rows)
        actual, first_bytes = run_pipeline()
        assert actual == expected, "Rust pipeline produced incorrect results for a generated fixture"

        shuffled = list(rows)
        random.SystemRandom().shuffle(shuffled)
        if shuffled == rows:
            shuffled.reverse()
        write_clicks(shuffled)
        actual_shuffled, second_bytes = run_pipeline()
        assert actual_shuffled == expected, "Rust pipeline changed its aggregation after input shuffling"
        assert second_bytes == first_bytes, "output.json is not byte-for-byte reproducible across input orders"

        # Execute the submitted reproducibility script rather than trusting its prewritten status.
        write_clicks(rows)
        STATUS.write_text("NOT_RUN\n")
        for path in (HOME / "out1.json", HOME / "out2.json"):
            if path.exists():
                path.unlink()
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=str(HOME),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert result.returncode == 0, f"Reproducibility script failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert STATUS.is_file() and STATUS.read_text().strip() == "REPRODUCIBLE", "Executed script did not report REPRODUCIBLE"

        out1 = HOME / "out1.json"
        out2 = HOME / "out2.json"
        assert out1.is_file(), "Executed reproducibility script did not create /home/user/out1.json"
        assert out2.is_file(), "Executed reproducibility script did not create /home/user/out2.json"
        assert out1.read_bytes() == out2.read_bytes(), "Reproducibility outputs are not exactly identical"
        assert json.loads(out1.read_text()) == expected, "out1.json does not contain the generated fixture's correct result"
        assert json.loads(out2.read_text()) == expected, "out2.json does not contain the generated fixture's correct result"
    finally:
        for path, content in saved.items():
            if content is None:
                if path.exists():
                    if path.is_dir():
                        shutil.rmtree(path)
                    else:
                        path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
