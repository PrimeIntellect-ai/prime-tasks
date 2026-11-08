#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile

PROJECT = "/home/user/project"
ORGANIZER = os.path.join(PROJECT, "organizer.sh")
TEST_SCRIPT = os.path.join(PROJECT, "test_organizer.sh")
QUEUES = os.path.join(PROJECT, "queues")


def clean_queues():
    if os.path.exists(QUEUES):
        shutil.rmtree(QUEUES)
    os.makedirs(QUEUES, exist_ok=True)


def test_rust_bug_txt():
    bug_file = os.path.join(PROJECT, "rust_bug.txt")
    assert os.path.isfile(bug_file), f"File {bug_file} does not exist."
    with open(bug_file, "r", encoding="utf-8") as f:
        original = f.read().strip()
    content = original.lower()

    # Preserve the original keyword assertion.
    keywords = ["clone", "moved", "reference", "copy"]
    assert any(word in content for word in keywords), (
        f"{bug_file} does not contain a valid explanation of the ownership bug "
        "(missing expected keywords)."
    )

    assert original, f"{bug_file} is empty."
    assert len(re.findall(r"[.!?]+", original)) == 1 and original[-1] in ".!?", (
        f"{bug_file} must contain exactly one sentence."
    )
    assert "file_name" in content, "The explanation must identify file_name."
    assert "push" in content or "vector" in content or "vec" in content, (
        "The explanation must identify the move into the vector."
    )
    explains_clone = "clone" in content and ("before" in content or "instead" in content)
    explains_reordering = (
        ("print" in content or "println" in content)
        and "before" in content
        and ("push" in content or "move" in content)
    )
    assert explains_clone or explains_reordering, (
        "The sentence must explain a valid fix: clone file_name before pushing it, "
        "or print it before it is moved."
    )


def test_organizer_executable():
    assert os.path.isfile(ORGANIZER), f"Script {ORGANIZER} does not exist."
    assert os.access(ORGANIZER, os.X_OK), f"Script {ORGANIZER} is not executable."


def run_organizer_case(names):
    clean_queues()
    with tempfile.TemporaryDirectory() as source:
        expected_contents = {}
        for index, name in enumerate(reversed(names)):
            path = os.path.join(source, name)
            data = f"payload-{index}-{name}".encode()
            with open(path, "wb") as f:
                f.write(data)
            expected_contents[name] = data

        # These are not regular files directly in the source directory and must remain.
        nested = os.path.join(source, "nested")
        os.mkdir(nested)
        with open(os.path.join(nested, "nested_file.txt"), "w", encoding="utf-8") as f:
            f.write("nested")
        os.symlink(os.path.join(nested, "nested_file.txt"), os.path.join(source, "link_to_file"))
        os.mkfifo(os.path.join(source, "named_pipe"))

        env = os.environ.copy()
        env["LC_ALL"] = "C"
        result = subprocess.run(
            [ORGANIZER, source], cwd=PROJECT, env=env,
            capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"{ORGANIZER} failed independently with code {result.returncode}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )

        ordered = sorted(names)
        expected_queues = [ordered[i:i + 5] for i in range(0, len(ordered), 5)]
        actual_queue_dirs = sorted(
            entry for entry in os.listdir(QUEUES)
            if entry.startswith("queue_") and os.path.isdir(os.path.join(QUEUES, entry))
        )
        expected_dir_names = [f"queue_{i}" for i in range(1, len(expected_queues) + 1)]
        assert actual_queue_dirs == expected_dir_names, (
            f"Expected queue directories {expected_dir_names}, got {actual_queue_dirs}."
        )

        for number, expected_names in enumerate(expected_queues, 1):
            queue = os.path.join(QUEUES, f"queue_{number}")
            assert os.path.isdir(queue), f"queue_{number} was not created."
            actual_names = sorted(os.listdir(queue))
            assert actual_names == expected_names, (
                f"queue_{number} should contain {expected_names}, got {actual_names}."
            )
            assert len(actual_names) <= 5, f"queue_{number} exceeds capacity 5."
            for name in actual_names:
                path = os.path.join(queue, name)
                assert os.path.isfile(path) and not os.path.islink(path), (
                    f"{path} is not a moved regular file."
                )
                with open(path, "rb") as f:
                    assert f.read() == expected_contents[name], f"Contents of {name} changed."

        for name in names:
            assert not os.path.exists(os.path.join(source, name)), f"{name} was not moved."
        assert os.path.isfile(os.path.join(nested, "nested_file.txt")), "Nested file was moved."
        assert os.path.islink(os.path.join(source, "link_to_file")), "Symlink was moved."
        assert stat.S_ISFIFO(os.lstat(os.path.join(source, "named_pipe")).st_mode), "FIFO was moved."


def test_organizer_logic_general_inputs_and_ordering():
    names = [
        ".hidden.txt", "alpha.txt", "bravo 2.txt", "charlie.txt", "delta.txt",
        "echo.txt", "foxtrot.txt", "golf.txt", "hotel.txt", "india.txt",
        "juliet.txt", "kilo.txt", "lima.txt", "mike.txt", "november.txt",
        "oscar.txt", "papa.txt"
    ]
    for count in (1, 5, 6, 12, 17):
        run_organizer_case(names[:count])


def test_test_organizer_executable_and_passes():
    assert os.path.isfile(TEST_SCRIPT), f"Test script {TEST_SCRIPT} does not exist."
    assert os.access(TEST_SCRIPT, os.X_OK), f"Test script {TEST_SCRIPT} is not executable."

    clean_queues()
    result = subprocess.run(
        [TEST_SCRIPT], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{TEST_SCRIPT} failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    # A no-op test suite would also accept this deliberately incorrect 4/5/3 organizer.
    with open(ORGANIZER, "rb") as f:
        saved_organizer = f.read()
    saved_mode = os.stat(ORGANIZER).st_mode
    mutant = r'''#!/bin/bash
set -e
src=$1
mkdir -p /home/user/project/queues/queue_1 /home/user/project/queues/queue_2 /home/user/project/queues/queue_3
mapfile -d '' files < <(find "$src" -maxdepth 1 -type f -print0 | sort -z)
for i in "${!files[@]}"; do
    if (( i < 4 )); then q=1; elif (( i < 9 )); then q=2; else q=3; fi
    mv -- "${files[$i]}" "/home/user/project/queues/queue_$q/"
done
'''
    try:
        with open(ORGANIZER, "w", encoding="utf-8") as f:
            f.write(mutant)
        os.chmod(ORGANIZER, 0o755)
        clean_queues()
        bad_result = subprocess.run(
            [TEST_SCRIPT], cwd=PROJECT, capture_output=True, text=True, timeout=20
        )
        assert bad_result.returncode != 0, (
            "test_organizer.sh accepted an organizer producing 4/5/3 files instead of 5/5/2; "
            "it must execute organizer.sh and enforce its assertions."
        )
    finally:
        with open(ORGANIZER, "wb") as f:
            f.write(saved_organizer)
        os.chmod(ORGANIZER, stat.S_IMODE(saved_mode))
        clean_queues()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
