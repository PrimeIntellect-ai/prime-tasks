#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import random
import shutil
import string
import subprocess
import tempfile

ORACLE_BIN = "/app/bin/gpak-ref"
ORACLE_SOURCE = "/tmp/gpak_ref.py"
AGENT_SCRIPT = "/home/user/gpak.py"


def generate_random_string(length=8):
    chars = string.ascii_letters + string.digits + "_.-"
    return ''.join(random.choice(chars) for _ in range(length))


def create_random_file(path, file_type, size):
    if file_type == "text/gcode":
        with open(path, "w", encoding="utf-8") as f:
            lines = []
            current_size = 0
            while current_size < size:
                cmd = random.choice(["G0", "G1", "M104", "M109", "G28"])
                line = f"  {cmd} X{random.randint(0, 100)} Y{random.randint(0, 100)}\n"
                lines.append(line)
                current_size += len(line)
            f.write("".join(lines))
    elif file_type == "application/x-executable":
        with open(path, "wb") as f:
            f.write(b"\x7fELF" + os.urandom(max(0, size - 4)))
    else:
        with open(path, "wb") as f:
            f.write(os.urandom(size))


def generate_random_directory(base_path, max_depth, num_files):
    directories = [base_path]
    for _ in range(num_files):
        depth = random.randint(1, max_depth)
        current_dir = base_path
        for _ in range(depth - 1):
            subdir = generate_random_string(5)
            current_dir = os.path.join(current_dir, subdir)
            os.makedirs(current_dir, exist_ok=True)
            if current_dir not in directories:
                directories.append(current_dir)

        target_dir = random.choice(directories)
        filename = generate_random_string(8)
        file_type = random.choice(["text/gcode", "application/x-executable", "random_binary"])
        if file_type == "text/gcode":
            filename += ".gcode"
        elif file_type == "application/x-executable":
            filename += ".elf"
        else:
            filename += ".bin"

        filepath = os.path.join(target_dir, filename)
        size = random.randint(0, 50000)
        create_random_file(filepath, file_type, size)


@contextlib.contextmanager
def oracle_unavailable():
    """Remove the supplied implementation while agent artifacts are exercised."""
    saved = []
    for path in (ORACLE_BIN, ORACLE_SOURCE):
        if os.path.lexists(path):
            st = os.stat(path)
            with open(path, "rb") as f:
                data = f.read()
            saved.append((path, data, st.st_mode & 0o7777))
            os.unlink(path)
    try:
        yield
    finally:
        for path, data, mode in saved:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, mode)


def assert_agent_is_python():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    with open(AGENT_SCRIPT, "rb") as f:
        agent_data = f.read()
    source = agent_data.decode("utf-8")
    compile(source, AGENT_SCRIPT, "exec")

    for reference in (ORACLE_BIN, ORACLE_SOURCE):
        if os.path.isfile(reference):
            with open(reference, "rb") as f:
                assert agent_data != f.read(), "Agent submission is byte-identical to a supplied reference artifact"


def snapshot_tree(root):
    result = {}
    for current, dirs, files in os.walk(root):
        dirs.sort()
        files.sort()
        for filename in files:
            full = os.path.join(current, filename)
            rel = os.path.relpath(full, root)
            with open(full, "rb") as f:
                result[rel] = f.read()
    return result


def test_fuzz_equivalence():
    random.seed(42)
    assert_agent_is_python()

    for i in range(5):
        with tempfile.TemporaryDirectory() as tmpdir:
            input_dir = os.path.join(tmpdir, "input")
            os.makedirs(input_dir)
            num_files = random.randint(1, 20)
            generate_random_directory(input_dir, max_depth=3, num_files=num_files)

            oracle_out = os.path.join(tmpdir, "oracle.gpak")
            agent_out = os.path.join(tmpdir, "agent.gpak")
            subprocess.run([ORACLE_BIN, "pack", oracle_out, input_dir], check=True)

            with oracle_unavailable():
                res = subprocess.run(
                    ["python3", AGENT_SCRIPT, "pack", agent_out, input_dir],
                    capture_output=True,
                    text=True,
                )
            assert res.returncode == 0, f"Agent script failed:\n{res.stderr}"
            assert os.path.exists(agent_out), "Agent script did not produce output file"

            with open(oracle_out, "rb") as f:
                oracle_data = f.read()
            with open(agent_out, "rb") as f:
                agent_data = f.read()
            assert agent_data == oracle_data, f"Output mismatch on random input directory {i}."


def test_unpack_implementation_without_oracle():
    random.seed(2025)
    assert_agent_is_python()

    for i in range(3):
        with tempfile.TemporaryDirectory() as tmpdir:
            input_dir = os.path.join(tmpdir, "input")
            output_dir = os.path.join(tmpdir, "output")
            archive = os.path.join(tmpdir, "input.gpak")
            os.makedirs(input_dir)
            generate_random_directory(input_dir, max_depth=3, num_files=12)
            expected = snapshot_tree(input_dir)

            subprocess.run([ORACLE_BIN, "pack", archive, input_dir], check=True)
            with oracle_unavailable():
                res = subprocess.run(
                    ["python3", AGENT_SCRIPT, "unpack", archive, output_dir],
                    capture_output=True,
                    text=True,
                )
            assert res.returncode == 0, f"Agent unpack failed on case {i}:\n{res.stderr}"
            assert os.path.isdir(output_dir), "Agent unpack did not create the output directory"
            assert snapshot_tree(output_dir) == expected, f"Unpacked files differ on case {i}"


def test_end_to_end_pipeline():
    random.seed(1337)
    with tempfile.TemporaryDirectory() as tmpdir:
        input_dir = os.path.join(tmpdir, "input")
        os.makedirs(input_dir)
        generate_random_directory(input_dir, max_depth=2, num_files=10)

        expected_lines = 0
        for root, _, files in os.walk(input_dir):
            for file in files:
                if file.endswith(".gcode"):
                    with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                        for line in f:
                            stripped = line.lstrip()
                            if stripped.startswith("G0") or stripped.startswith("G1"):
                                expected_lines += 1

        gpak_filename = "test_upload_123.gpak"
        gpak_path = os.path.join(tmpdir, gpak_filename)
        subprocess.run([ORACLE_BIN, "pack", gpak_path, input_dir], check=True)

        base_name = "test_upload_123"
        redis_key = f"gpak:{base_name}:movement_lines"
        subprocess.run(["redis-cli", "del", redis_key], check=True, capture_output=True, text=True)

        url = "http://localhost:8080/api/upload"
        with oracle_unavailable():
            res = subprocess.run(
                ["curl", "-sS", "-X", "POST", "-F", f"file=@{gpak_path}", url],
                capture_output=True,
                text=True,
            )
        assert res.returncode == 0, f"Upload request failed: {res.stderr}"

        redis_res = subprocess.run(["redis-cli", "get", redis_key], capture_output=True, text=True)
        assert redis_res.returncode == 0, "Failed to query redis"
        val = redis_res.stdout.strip()
        assert val != "", f"Redis key {redis_key} not found or empty"
        assert val == str(expected_lines), f"Expected {expected_lines} movement lines in Redis, got {val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
