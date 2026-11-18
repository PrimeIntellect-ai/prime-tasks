#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import tempfile
import uuid


def test_source_file_exists():
    assert os.path.isfile("/home/user/etl_pipeline.cpp"), "/home/user/etl_pipeline.cpp does not exist."


def test_executable_exists():
    assert os.path.isfile("/home/user/etl_pipeline"), "/home/user/etl_pipeline does not exist. Did you compile it?"
    assert os.access("/home/user/etl_pipeline", os.X_OK), "/home/user/etl_pipeline is not executable."


def test_etl_results_content():
    expected_content = "user_id,weighted_out_degree\n106,1000\n101,900\n104,300\n102,200"
    assert os.path.isfile("/home/user/etl_results.csv"), "/home/user/etl_results.csv does not exist."
    with open("/home/user/etl_results.csv", "r") as f:
        content = f.read().strip()
    assert content == expected_content, "The content of /home/user/etl_results.csv is incorrect for the provided dataset."


def test_etl_pipeline_logic_hidden_dataset():
    """Verify the executable logic using a dynamically generated hidden dataset."""
    with tempfile.TemporaryDirectory() as tmpdir:
        entities_path = os.path.join(tmpdir, "entities.dat")
        edges_path = os.path.join(tmpdir, "edges.dat")
        out_path = os.path.join(tmpdir, "out.csv")

        with open(entities_path, "w") as f:
            f.write("201,Zack,Engineering,Manager\n")
            f.write("202,Yara,Engineering,Dev\n")
            f.write("203,Xena,Sales,Rep\n")

        with open(edges_path, "w") as f:
            f.write("m1,201,202,100,50\n")
            f.write("m2,201,203,110,25\n")
            f.write("m3,202,201,120,100\n")

        result = subprocess.run(
            ["/home/user/etl_pipeline", entities_path, edges_path, out_path],
            capture_output=True,
            text=True
        )

        assert result.returncode == 0, f"Executable failed with return code {result.returncode}. Stderr: {result.stderr}"
        assert os.path.isfile(out_path), "Executable did not create the output file when run on the hidden dataset."

        with open(out_path, "r") as f:
            content = f.read().strip()

        expected_content = "user_id,weighted_out_degree\n202,100\n201,75"
        assert content == expected_content, f"The logic of the ETL pipeline is incorrect on a hidden dataset.\nExpected:\n{expected_content}\nGot:\n{content}"


def expected_output(entities, edges):
    totals = {user_id: 0 for user_id, _, _, _ in entities}
    for _, sender, _, _, size in edges:
        if sender in totals:
            totals[sender] += size
    rows = [(user_id, totals[user_id]) for user_id, _, department, _ in entities
            if department == "Engineering"]
    rows.sort(key=lambda row: (-row[1], row[0]))
    return "user_id,weighted_out_degree\n" + "\n".join(
        f"{user_id},{weight}" for user_id, weight in rows
    )


def run_case(executable, entities, edges, case_dir):
    entities_path = os.path.join(case_dir, "entities.dat")
    edges_path = os.path.join(case_dir, "edges.dat")
    out_path = os.path.join(case_dir, "result.csv")

    with open(entities_path, "w") as f:
        for row in entities:
            f.write(",".join(map(str, row)) + "\n")
    with open(edges_path, "w") as f:
        for row in edges:
            f.write(",".join(map(str, row)) + "\n")

    result = subprocess.run(
        [executable, entities_path, edges_path, out_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    assert os.path.isfile(out_path), f"{executable} did not create the requested output file."
    with open(out_path, "r") as f:
        actual = f.read().strip()
    expected = expected_output(entities, edges).strip()
    assert actual == expected, f"Expected:\n{expected}\nGot:\n{actual}"


def test_randomized_etl_logic_and_cpp_source():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "rebuilt_etl_pipeline")
        compile_result = subprocess.run(
            ["g++", "-O3", "-std=c++17", "/home/user/etl_pipeline.cpp", "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "The submitted C++ source does not compile with the required command. "
            f"Stderr: {compile_result.stderr}"
        )

        for case_number in range(6):
            ids = rng.sample(range(10000, 99999), 9)
            engineering = set(ids[:6])
            entities = []
            for index, user_id in enumerate(ids):
                department = "Engineering" if user_id in engineering else rng.choice(["Sales", "HR", "Finance"])
                entities.append((user_id, f"User{uuid.uuid4().hex[:10]}", department, f"Role{index}"))
            rng.shuffle(entities)

            # Leave two Engineering users with no outgoing messages, exercising zero
            # centrality and numeric user-id tie ordering.
            zero_senders = set(ids[:2])
            allowed_senders = [user_id for user_id in ids if user_id not in zero_senders]
            edges = []
            timestamp = rng.randrange(1_000_000, 9_000_000)
            for edge_number in range(rng.randint(30, 55)):
                sender = rng.choice(allowed_senders)
                receiver = rng.choice(ids)
                size = rng.randint(1, 250000)
                edges.append((uuid.uuid4().hex, sender, receiver, timestamp + edge_number, size))

            # Force repeated sender/receiver pairs so edge aggregation is exercised.
            sender = rng.choice(allowed_senders)
            receiver = rng.choice(ids)
            edges.append((uuid.uuid4().hex, sender, receiver, timestamp + 1000, rng.randint(10, 5000)))
            edges.append((uuid.uuid4().hex, sender, receiver, timestamp + 1001, rng.randint(10, 5000)))
            rng.shuffle(edges)

            for executable_index, executable in enumerate(("/home/user/etl_pipeline", rebuilt)):
                case_dir = os.path.join(tmpdir, f"case_{case_number}_{executable_index}")
                os.mkdir(case_dir)
                run_case(executable, entities, edges, case_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
