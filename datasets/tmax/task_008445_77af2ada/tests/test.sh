#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import shutil
import subprocess
import tempfile
from collections import deque

import pytest


def test_cpp_file_exists():
    cpp_file = "/home/user/config_tracker.cpp"
    assert os.path.isfile(cpp_file), f"C++ source file {cpp_file} does not exist."


def test_stats_output_exists():
    output_file = "/home/user/stats_output.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist. Did you compile and run your C++ program?"


def test_stats_output_content():
    output_file = "/home/user/stats_output.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    expected_lines = [
        "update_01.txt,VALID,2,11.50",
        "update_02.txt,VALID,2,9.50",
        "update_03.txt,INVALID,0,0.00",
        "update_04.txt,VALID,2,7.17",
        "update_05.txt,VALID,1,5.00"
    ]

    with open(output_file, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_file}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {output_file} is incorrect.\nExpected: {expected}\nActual: {actual}"


def _expected_for(directory):
    window = deque(maxlen=3)
    result = []

    for path in sorted(directory.iterdir(), key=lambda p: p.name):
        if not path.is_file() or path.suffix != ".txt":
            continue

        data = path.read_bytes()
        if b"\xff" in data:
            result.append(f"{path.name},INVALID,0,0.00")
            continue

        text = data.decode("utf-8")
        lengths = []
        for line in text.splitlines():
            if not line or "=" not in line:
                continue
            _, value = line.split("=", 1)
            lengths.append(len(value))

        window.append((sum(lengths), len(lengths)))
        total_length = sum(item[0] for item in window)
        total_keys = sum(item[1] for item in window)
        average = total_length / total_keys if total_keys else 0.0
        result.append(f"{path.name},VALID,{len(lengths)},{average:.2f}")

    return result


def test_zz_source_compiles_and_processes_unseen_inputs():
    source = pathlib.Path("/home/user/config_tracker.cpp")
    updates = pathlib.Path("/home/user/config_updates")
    output = pathlib.Path("/home/user/stats_output.csv")
    executable = pathlib.Path("/tmp/config_tracker_verifier_bin")

    token = secrets.token_hex(6)
    backup_root = pathlib.Path(tempfile.mkdtemp(prefix="config_tracker_backup_"))
    backup_updates = backup_root / "config_updates"
    shutil.copytree(updates, backup_updates)
    old_output = output.read_bytes() if output.exists() else None

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", str(source), "-o", str(executable)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, "C++ source did not compile:\n" + compile_result.stderr
        assert executable.is_file() and os.access(executable, os.X_OK)

        shutil.rmtree(updates)
        updates.mkdir(mode=0o777)
        os.chmod(updates, 0o777)

        fixtures = {
            f"a_{token}.txt": (
                f"alpha={'界' * (2 + secrets.randbelow(4))}\n"
                f"beta={'é' * (3 + secrets.randbelow(5))}\n"
                "ignored line\n\n"
            ).encode("utf-8"),
            f"b_{token}.txt": b"looks=valid\ncorrupt=payload\xffbytes\n",
            f"c_{token}.txt": b"no delimiter here\n\n",
            f"d_{token}.txt": (
                f"arabic={'مرحبا' * (1 + secrets.randbelow(3))}\n"
                f"emoji={'🙂' * (2 + secrets.randbelow(4))}\n"
            ).encode("utf-8"),
            f"e_{token}.txt": b"bad=discard all of this\xff\nother=also discarded\n",
            f"f_{token}.txt": (
                f"first={'x' * (4 + secrets.randbelow(8))}\n"
                "empty=\n"
            ).encode("utf-8"),
            f"g_{token}.txt": (
                f"equals=value=with=equals-{token}\n"
                f"cjk={'早上好' * (1 + secrets.randbelow(2))}\n"
            ).encode("utf-8"),
        }

        for name, data in fixtures.items():
            (updates / name).write_bytes(data)
        (updates / f"ignored_{token}.dat").write_text("key=must not appear\n", encoding="utf-8")
        os.chmod(updates, 0o777)
        for path in updates.iterdir():
            os.chmod(path, 0o666)

        expected = _expected_for(updates)
        if output.exists():
            output.unlink()

        run_result = subprocess.run(
            ["runuser", "-u", "user", "--", str(executable)],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, "Compiled program failed when executed:\n" + run_result.stderr
        assert output.is_file(), "Executing the compiled program did not create stats_output.csv"

        actual = output.read_text(encoding="utf-8").splitlines()
        assert actual == expected, "Program produced incorrect results for unseen inputs.\nExpected:\n" + "\n".join(expected) + "\nActual:\n" + "\n".join(actual)
    finally:
        if updates.exists():
            shutil.rmtree(updates)
        shutil.copytree(backup_updates, updates)
        if old_output is None:
            if output.exists():
                output.unlink()
        else:
            output.write_bytes(old_output)
        shutil.rmtree(backup_root, ignore_errors=True)
        if executable.exists():
            executable.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
