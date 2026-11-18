#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import string
import subprocess
import pytest

HOME = "/home/user"
USERS = "/home/user/data/users.csv"
LEGACY = "/home/user/data/legacy_hashes.csv"


def run_pipeline():
    return subprocess.run(
        ["/home/user/run.sh"],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=True,
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    for path in ("/home/user/process", "/home/user/bench.txt", "/home/user/final.csv"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    run_pipeline()


def test_process_c_exists():
    assert os.path.isfile("/home/user/process.c"), "/home/user/process.c does not exist."


def test_compiled_process_exists_and_is_executable():
    path = "/home/user/process"
    assert os.path.isfile(path), f"{path} was not produced by run.sh."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_run_sh_exists_and_executable():
    file_path = "/home/user/run.sh"
    assert os.path.isfile(file_path), f"{file_path} does not exist."
    st = os.stat(file_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"{file_path} is not executable."


def test_run_sh_contents():
    with open("/home/user/run.sh", "r") as f:
        content = f.read()
    assert "gcc" in content, "run.sh does not contain 'gcc'"
    assert "/usr/bin/time" in content, "run.sh does not contain '/usr/bin/time'"
    assert "join" in content, "run.sh does not contain 'join'"


def test_bench_txt_exists():
    assert os.path.isfile("/home/user/bench.txt"), "/home/user/bench.txt does not exist."
    assert os.path.getsize("/home/user/bench.txt") > 0, "/home/user/bench.txt is empty."


def test_final_csv_content():
    file_path = "/home/user/final.csv"
    assert os.path.isfile(file_path), f"{file_path} does not exist."
    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "1,98,100",
        "3,22,200",
        "4,98,300",
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, f"Content of {file_path} does not match the expected joined output."


def xor_hash(text):
    value = 0
    for character in text:
        value ^= ord(character)
    return value


def test_process_on_generated_input():
    alphabet = string.ascii_letters + string.digits + " !?_-"
    texts = ["".join(secrets.choice(alphabet) for _ in range(19)) for _ in range(3)]
    input_text = (
        f"731,valid@example.com,{texts[0]}\n"
        f"842,invalid.example.com,{texts[1]}\n"
        f"953,also@valid.net,{texts[2]}\n"
    )
    result = subprocess.run(
        ["/home/user/process"],
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=True,
    )
    expected = f"731,{xor_hash(texts[0])}\n953,{xor_hash(texts[2])}\n"
    assert result.stdout == expected


def test_pipeline_on_generated_unsorted_data():
    with open(USERS, "rb") as f:
        original_users = f.read()
    with open(LEGACY, "rb") as f:
        original_legacy = f.read()

    ids = secrets.SystemRandom().sample(range(1100, 9000), 4)
    valid_ids = [ids[0], ids[2], ids[3]]
    texts = [secrets.token_hex(11) for _ in range(4)]
    legacy_values = {record_id: secrets.randbelow(900000) + 100000 for record_id in valid_ids}

    users_content = (
        f"{ids[2]},third@example.com,{texts[2]}\n"
        f"{ids[1]},invalid.example.com,{texts[1]}\n"
        f"{ids[3]},fourth@example.com,{texts[3]}\n"
        f"{ids[0]},first@example.com,{texts[0]}\n"
    )
    extra_id = 99999
    legacy_rows = [(record_id, legacy_values[record_id]) for record_id in valid_ids]
    legacy_rows.append((extra_id, 424242))
    legacy_content = "".join(f"{record_id},{value}\n" for record_id, value in sorted(legacy_rows))

    text_by_id = {ids[0]: texts[0], ids[2]: texts[2], ids[3]: texts[3]}
    expected = [
        f"{record_id},{xor_hash(text_by_id[record_id])},{legacy_values[record_id]}"
        for record_id in sorted(valid_ids)
    ]

    try:
        with open(USERS, "w") as f:
            f.write(users_content)
        with open(LEGACY, "w") as f:
            f.write(legacy_content)
        for path in ("/home/user/bench.txt", "/home/user/final.csv"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        run_pipeline()
        with open("/home/user/final.csv", "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected
        assert os.path.isfile("/home/user/bench.txt")
        assert os.path.getsize("/home/user/bench.txt") > 0
    finally:
        with open(USERS, "wb") as f:
            f.write(original_users)
        with open(LEGACY, "wb") as f:
            f.write(original_legacy)
        run_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
