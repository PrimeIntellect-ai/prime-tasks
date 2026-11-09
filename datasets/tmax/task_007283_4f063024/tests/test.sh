#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import uuid


def test_workspace_extracted():
    """Test that the archive was reconstructed and extracted to /home/user/workspace/."""
    workspace = "/home/user/workspace"
    assert os.path.isdir(workspace), f"{workspace} directory is missing."

    manifest = os.path.join(workspace, "manifest.csv")
    assert os.path.isfile(manifest), f"{manifest} is missing."

    raw_dir = os.path.join(workspace, "raw")
    assert os.path.isdir(raw_dir), f"{raw_dir} directory is missing."

    links_dir = os.path.join(workspace, "links")
    assert os.path.isdir(links_dir), f"{links_dir} directory is missing."

    expected_files = {
        "manifest.csv": (
            "path,description\n"
            "links/link_1.csv,batch_01\n"
            "links/link_2.csv,batch_02\n"
            "links/link_3.csv,batch_03_missing\n"
            "links/link_4.csv,batch_04\n"
        ),
        "raw/data1.csv": "sensor_a,10\nsensor_b,42\nsensor_c,99\n",
        "raw/data2.csv": "sensor_b,11\nsensor_a,15\n",
        "raw/data3.csv": "sensor_x,1\nsensor_a,25\nsensor_a,5\n",
    }
    for relative_path, expected in expected_files.items():
        path = os.path.join(workspace, relative_path)
        assert os.path.isfile(path), f"Extracted file {path} is missing."
        with open(path, "r", encoding="utf-8") as f:
            assert f.read() == expected, f"Extracted file {path} has incorrect contents."

    expected_links = {
        "link_1.csv": "../raw/data1.csv",
        "link_2.csv": "../raw/data2.csv",
        "link_3.csv": "../raw/missing.csv",
        "link_4.csv": "../raw/data3.csv",
    }
    for name, target in expected_links.items():
        path = os.path.join(links_dir, name)
        assert os.path.islink(path), f"{path} is not the expected symbolic link."
        assert os.readlink(path) == target, f"{path} points to the wrong target."


def test_c_program_files_exist():
    """Test that the C source and compiled executable exist."""
    source_file = "/home/user/aggregate.c"
    executable = "/home/user/aggregate"

    assert os.path.isfile(source_file), f"C source file {source_file} is missing."
    assert os.path.isfile(executable), f"Compiled executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."

    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable."


def test_sensor_a_total():
    """Test that the final output file contains the correct sum."""
    output_file = "/home/user/sensor_a_total.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content == "55", f"Expected '55' in {output_file}, but found '{content}'."


def test_program_and_source_on_fresh_inputs():
    """Compile the submitted source and exercise both binaries on unpredictable data."""
    rebuilt = f"/tmp/aggregate-rebuilt-{uuid.uuid4().hex}"
    compile_result = subprocess.run(
        ["gcc", "/home/user/aggregate.c", "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "aggregate.c does not compile with gcc:\n" + compile_result.stderr
    )

    workspace = "/home/user/workspace"
    backup = f"/home/user/.workspace-verifier-backup-{uuid.uuid4().hex}"
    output = "/home/user/sensor_a_total.txt"
    old_output = None
    if os.path.exists(output):
        with open(output, "rb") as f:
            old_output = f.read()

    os.rename(workspace, backup)
    rng = secrets.SystemRandom()

    try:
        for case_number in range(2):
            if os.path.lexists(workspace):
                shutil.rmtree(workspace)
            raw_dir = os.path.join(workspace, "raw")
            links_dir = os.path.join(workspace, "links")
            os.makedirs(raw_dir)
            os.makedirs(links_dir)

            token = secrets.token_hex(5)
            first_name = f"batch_{token}_a.csv"
            second_name = f"batch_{token}_b.csv"
            decoy_name = f"unlisted_{token}.csv"
            first_link = f"selected_{token}_one.csv"
            second_link = f"selected_{token}_two.csv"
            broken_link = f"broken_{token}.csv"

            first_rows = [
                ("sensor_a", rng.randint(101, 5000)),
                ("sensor_b", rng.randint(101, 5000)),
                ("sensor_a_extra", rng.randint(101, 5000)),
                ("sensor_a", rng.randint(101, 5000)),
            ]
            second_rows = [
                ("Sensor_a", rng.randint(101, 5000)),
                ("sensor_a", rng.randint(101, 5000)),
                ("sensor_x", rng.randint(101, 5000)),
            ]
            expected = sum(v for sensor, v in first_rows + second_rows if sensor == "sensor_a")

            def write_rows(name, rows):
                with open(os.path.join(raw_dir, name), "w", encoding="utf-8") as f:
                    for sensor, value in rows:
                        f.write(f"{sensor},{value}\n")

            write_rows(first_name, first_rows)
            write_rows(second_name, second_rows)
            write_rows(decoy_name, [("sensor_a", expected + rng.randint(5001, 9000))])

            os.symlink(f"../raw/{first_name}", os.path.join(links_dir, first_link))
            os.symlink(f"../raw/{second_name}", os.path.join(links_dir, second_link))
            os.symlink(f"../raw/does_not_exist_{token}.csv", os.path.join(links_dir, broken_link))

            with open(os.path.join(workspace, "manifest.csv"), "w", encoding="utf-8") as f:
                f.write("path,description\n")
                f.write(f"links/{first_link},generated first batch\n")
                f.write(f"links/{broken_link},generated missing batch\n")
                f.write(f"links/{second_link},generated second batch\n")

            for executable in ("/home/user/aggregate", rebuilt):
                if os.path.lexists(output):
                    os.unlink(output)
                result = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert result.returncode == 0, (
                    f"{executable} exited with {result.returncode}: {result.stderr}"
                )
                assert os.path.isfile(output), f"{executable} did not create {output}."
                with open(output, "r", encoding="utf-8") as f:
                    content = f.read().strip()
                assert content == str(expected), (
                    f"{executable} produced {content!r}; expected {expected} for generated case "
                    f"{case_number + 1}."
                )
    finally:
        if os.path.lexists(workspace):
            shutil.rmtree(workspace)
        os.rename(backup, workspace)
        if os.path.lexists(output):
            os.unlink(output)
        if old_output is not None:
            with open(output, "wb") as f:
                f.write(old_output)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
