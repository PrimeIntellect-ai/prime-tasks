#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess


def test_01_pipeline_script_exists_and_executable():
    """Verify that the pipeline script exists and is executable."""
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_02_cpp_processor_exists():
    """Verify that the C++ source file exists."""
    cpp_path = "/home/user/processor.cpp"
    assert os.path.isfile(cpp_path), f"{cpp_path} does not exist."


def test_03_clean_data_content():
    """Verify that clean_data.csv was created and filtered correctly."""
    clean_path = "/home/user/clean_data.csv"
    assert os.path.isfile(clean_path), f"{clean_path} does not exist."

    with open(clean_path, "r") as f:
        lines = f.read().strip().split("\n")

    for line in lines:
        if not line.strip():
            continue
        assert not line.startswith("id,category"), "clean_data.csv should not contain the header."
        cols = line.split(",")
        if len(cols) > 1:
            assert cols[1] != "IGNORE", "clean_data.csv should not contain rows with category IGNORE."


def test_04_final_output_content():
    """Verify the final output matches the expected result."""
    output_path = "/home/user/final_output.csv"
    assert os.path.isfile(output_path), f"{output_path} does not exist."

    expected_lines = [
        "id,category,distance",
        "u4,A,0.000",
        "u1,A,2.000",
        "u3,B,5.500",
        "u7,B,9.000",
        "u9,C,0.000",
        "u6,C,5.000",
    ]

    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {output_path} is incorrect. Expected: {expected_lines}, "
        f"but got: {actual_lines}"
    )


REFERENCE = (1.0, -1.0, 1.0, -1.0, 1.0)


def make_rows(categories, records_per_category, rng):
    distances = iter(rng.sample(range(2, 240), len(categories) * records_per_category))
    rows = []
    serial = 0
    for category in categories:
        for record_index in range(records_per_category):
            serial += 1
            distance = next(distances)
            portions = (distance / 8.0, distance / 8.0, distance / 4.0,
                        distance / 4.0, distance / 4.0)
            values = []
            for j, (base, offset) in enumerate(zip(REFERENCE, portions)):
                sign = -1.0 if (serial + j) % 2 else 1.0
                values.append(base + sign * offset)
            row_id = f"x{secrets.token_hex(4)}_{serial}"
            rows.append((row_id, category, values))
    rng.shuffle(rows)
    return rows


def csv_line(row):
    row_id, category, values = row
    return ",".join([row_id, category] + [f"{value:.3f}" for value in values])


def expected_output(rows):
    counts = {}
    selected = []
    for row_id, category, values in rows:
        if category == "IGNORE":
            continue
        count = counts.get(category, 0)
        if count >= 2:
            continue
        counts[category] = count + 1
        distance = sum(abs(value - ref) for value, ref in zip(values, REFERENCE))
        selected.append((category, distance, row_id))
    selected.sort(key=lambda item: (item[0], item[1]))
    return ["id,category,distance"] + [
        f"{row_id},{category},{distance:.3f}"
        for category, distance, row_id in selected
    ]


def read_nonempty(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_checked(command, timeout=30):
    result = subprocess.run(
        command,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_05_pipeline_and_cpp_process_unseen_data():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    # Exercise the complete pipeline on an unseen data set with excess strata,
    # exact IGNORE rows, and a category whose name merely starts with IGNORE.
    rows = make_rows(["ZETA", "ALPHA", "MIDDLE", "IGNOREX"], 4, rng)
    ignored = make_rows(["IGNORE"], 3, rng)
    rows.extend(ignored)
    rng.shuffle(rows)

    raw_lines = ["id,category,v1,v2,v3,v4,v5"] + [csv_line(row) for row in rows]
    with open("/home/user/raw_data.csv", "w") as f:
        f.write("\n".join(raw_lines) + "\n")

    for path in ("/home/user/clean_data.csv", "/home/user/final_output.csv", "/home/user/processor"):
        if os.path.lexists(path):
            os.remove(path)

    run_checked(["/home/user/pipeline.sh"])

    assert os.path.isfile("/home/user/processor"), "pipeline.sh did not create /home/user/processor"
    assert os.access("/home/user/processor", os.X_OK), "/home/user/processor is not executable"
    with open("/home/user/processor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/processor is not a compiled executable"

    expected_clean = [csv_line(row) for row in rows if row[1] != "IGNORE"]
    assert read_nonempty("/home/user/clean_data.csv") == expected_clean, (
        "pipeline.sh did not remove exactly the header and category IGNORE rows"
    )
    assert read_nonempty("/home/user/final_output.csv") == expected_output(rows)

    # Independently compile the submitted source and exercise that executable on
    # another clean stream, so a script that fabricates final_output.csv cannot pass.
    standalone_binary = "/tmp/submitted_processor"
    if os.path.exists(standalone_binary):
        os.remove(standalone_binary)
    run_checked([
        "g++", "-std=c++17", "-O3", "-o", standalone_binary,
        "/home/user/processor.cpp",
    ])
    with open(standalone_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    standalone_rows = make_rows(["Q_CAT", "B_CAT", "LONG_CATEGORY"], 5, rng)
    with open("/home/user/clean_data.csv", "w") as f:
        f.write("\n".join(csv_line(row) for row in standalone_rows) + "\n")
    if os.path.exists("/home/user/final_output.csv"):
        os.remove("/home/user/final_output.csv")

    run_checked([standalone_binary])
    assert os.path.isfile("/home/user/final_output.csv")
    assert read_nonempty("/home/user/final_output.csv") == expected_output(standalone_rows)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
