#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import subprocess
import uuid


def expected_manifest():
    log_dir = "/home/user/active_logs"
    expected_lines = []
    for root, _, files in os.walk(log_dir):
        for file in files:
            if file.endswith(".log"):
                filepath = os.path.join(root, file)
                if os.path.getsize(filepath) > 10:
                    with open(filepath, "rb") as f:
                        data = f.read()
                    expected_lines.append(f"{filepath} {sum(data) % 256}\n")
    expected_lines.sort()
    return expected_lines


def test_cpp_source_exists():
    assert os.path.isfile("/home/user/checksum_gen.cpp"), "C++ source file /home/user/checksum_gen.cpp is missing."


def test_cpp_executable_exists():
    assert os.path.isfile("/home/user/checksum_gen"), "Compiled executable /home/user/checksum_gen is missing."
    assert os.access("/home/user/checksum_gen", os.X_OK), "/home/user/checksum_gen is not executable."
    with open("/home/user/checksum_gen", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/checksum_gen is not a compiled executable."


def test_bash_script_exists():
    assert os.path.isfile("/home/user/backup.sh"), "Bash script /home/user/backup.sh is missing."


def test_backup_manifest_correctness():
    manifest_path = "/home/user/backup_manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing. Did you run backup.sh?"

    expected_lines = expected_manifest()
    with open(manifest_path, "r") as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, (
        f"Manifest contents are incorrect.\n"
        f"Expected:\n{''.join(expected_lines)}\n"
        f"Got:\n{''.join(actual_lines)}"
    )


def exercise_checksum_program(program):
    token = uuid.uuid4().hex
    work = f"/tmp/checksum-test-{token}"
    os.makedirs(work)
    first = os.path.join(work, "first file.log")
    second = os.path.join(work, "second.log")
    empty = os.path.join(work, "empty.log")
    missing = os.path.join(work, "missing.log")

    first_data = ("Generated-" + token + "\nLine two!").encode("ascii")
    second_data = b"0123456789abcdef\n"
    with open(first, "wb") as f:
        f.write(first_data)
    with open(second, "wb") as f:
        f.write(second_data)
    open(empty, "wb").close()

    supplied = [second, missing, first, empty]
    result = subprocess.run(
        [program],
        input="".join(path + "\n" for path in supplied),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"{program} failed: {result.stderr}"
    expected = (
        f"{second} {sum(second_data) % 256}\n"
        f"{first} {sum(first_data) % 256}\n"
        f"{empty} 0\n"
    )
    assert result.stdout == expected, (
        f"Incorrect checksum generator output. Expected {expected!r}, got {result.stdout!r}"
    )


def test_submitted_checksum_executable_behavior():
    exercise_checksum_program("/home/user/checksum_gen")


def test_cpp_source_compiles_and_behaves():
    rebuilt = f"/tmp/rebuilt-checksum-{uuid.uuid4().hex}"
    result = subprocess.run(
        ["g++", "-std=c++17", "/home/user/checksum_gen.cpp", "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"checksum_gen.cpp does not compile:\n{result.stderr}"
    exercise_checksum_program(rebuilt)


def test_backup_script_runs_pipeline_on_dynamic_files():
    token = uuid.uuid4().hex
    root = "/home/user/active_logs"
    nested = os.path.join(root, f"nested-{token}")
    os.makedirs(nested)

    generated = {
        os.path.join(root, f"eligible space {token}.log"): ("alpha-" + token).encode("ascii"),
        os.path.join(nested, f"deep-{token}.log"): ("beta-data-" + token + "\n").encode("ascii"),
        os.path.join(root, f"exactly-ten-{token}.log"): b"0123456789",
        os.path.join(root, f"short-{token}.log"): b"short",
        os.path.join(root, f"wrong-{token}.txt"): ("not-a-log-" + token).encode("ascii"),
        os.path.join(root, f"upper-{token}.LOG"): ("upper-case-" + token).encode("ascii"),
    }
    for path, data in generated.items():
        with open(path, "wb") as f:
            f.write(data)

    executable = "/home/user/checksum_gen"
    saved = f"/tmp/checksum_gen.saved.{token}"
    capture = f"/tmp/checksum-input.{token}"
    invocations = f"/tmp/checksum-invocations.{token}"
    os.rename(executable, saved)
    wrapper = (
        "#!/bin/bash\n"
        f"printf 'x\\n' >> {shlex.quote(invocations)}\n"
        f"tee -a {shlex.quote(capture)} | {shlex.quote(saved)}\n"
    )
    with open(executable, "w") as f:
        f.write(wrapper)
    os.chmod(executable, 0o755)

    try:
        result = subprocess.run(
            ["bash", "/home/user/backup.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            env={**os.environ, "LC_ALL": "C"},
        )
    finally:
        if os.path.lexists(executable):
            os.unlink(executable)
        os.rename(saved, executable)

    assert result.returncode == 0, f"backup.sh failed:\n{result.stderr}"
    assert os.path.isfile(invocations), "backup.sh did not invoke /home/user/checksum_gen."
    with open(invocations, "r") as f:
        calls = f.readlines()
    assert len(calls) == 1, "backup.sh must pipe one find result stream into checksum_gen."
    assert os.path.isfile(capture), "checksum_gen received no piped file list from backup.sh."

    eligible_paths = []
    for walk_root, _, files in os.walk(root):
        for name in files:
            path = os.path.join(walk_root, name)
            if name.endswith(".log") and os.path.getsize(path) > 10:
                eligible_paths.append(path)
    with open(capture, "r") as f:
        received_paths = [line.rstrip("\n") for line in f]
    assert sorted(received_paths) == sorted(eligible_paths), (
        "backup.sh did not pipe exactly the .log files strictly larger than 10 bytes "
        "from find into /home/user/checksum_gen."
    )

    with open("/home/user/backup_manifest.txt", "r") as f:
        actual_lines = f.readlines()
    expected_lines = expected_manifest()
    assert actual_lines == expected_lines, (
        f"backup.sh produced an incorrect or unsorted manifest.\n"
        f"Expected:\n{''.join(expected_lines)}\nGot:\n{''.join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
