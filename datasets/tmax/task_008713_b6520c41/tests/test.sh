#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def expected_output(data, masters):
    lines = []
    for raw_line in data.splitlines():
        if not raw_line:
            continue
        row_id, raw_name = raw_line.split(',', 1)
        normalized = raw_name.strip().lower()
        distances = [levenshtein(normalized, master) for master in masters]
        best_index = min(range(len(masters)), key=lambda i: distances[i])
        lines.append(f"{row_id},{normalized},{masters[best_index]},{distances[best_index]}")
    return "\n".join(lines) + "\n"


def test_processed_data_csv():
    file_path = "/home/user/remote_out/processed_data.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. Did the pipeline run?"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "1,alice jones,alice jones,0",
        "2,bobby,bob,2",
        "3,charlie brown,charlie brown,0",
        "4,david   smith,david smith,2"
    ]

    actual_lines = [line.strip() for line in content.split("\n") if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in processed_data.csv, got {len(actual_lines)}"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'"


def test_crontab_entry():
    file_path = "/home/user/crontab_entry.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content.startswith("0 * * * *"), f"Cron entry should start with '0 * * * *', got: '{content}'"
    assert "/home/user/local_process/pipeline.sh" in content, f"Cron entry should contain '/home/user/local_process/pipeline.sh', got: '{content}'"


def test_pipeline_script_exists_and_executable():
    file_path = "/home/user/local_process/pipeline.sh"
    assert os.path.isfile(file_path), f"Pipeline script {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"Pipeline script {file_path} is not executable."


def test_matcher_executable_exists():
    file_path = "/home/user/local_process/matcher"
    assert os.path.isfile(file_path), f"Compiled C++ program {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"Compiled C++ program {file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "matcher must be a compiled executable, not a script or placeholder."

    source = "/home/user/local_process/matcher.cpp"
    assert os.path.isfile(source), f"C++ source file {source} is missing."
    assert os.path.getsize(source) > 0, f"C++ source file {source} is empty."


def test_matcher_on_derived_inputs_and_rebuilt_source():
    token = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(10))
    masters = [
        f"alpha {token}",
        f"alphi {token}",
        "bob",
        f"space  name {token}",
        "tiecat",
        "tiecut",
    ]
    data = (
        f"731,   ALPHA {token.upper()}  \n"
        f"842,bObBy   \n"
        f"953, tiecot\t\n"
        f"1064,  SPACE  NAME {token.upper()}  \n"
    )
    expected = expected_output(data, masters)

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "challenge.csv")
        master_path = os.path.join(td, "masters.txt")
        output_path = os.path.join(td, "result.csv")
        rebuilt_path = os.path.join(td, "rebuilt_matcher")
        with open(input_path, "w") as f:
            f.write(data)
        with open(master_path, "w") as f:
            f.write("\n".join(masters) + "\n")

        build = subprocess.run(
            ["g++", "-std=c++17", "/home/user/local_process/matcher.cpp", "-o", rebuilt_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert build.returncode == 0, f"matcher.cpp did not compile:\n{build.stderr}"

        for executable in ["/home/user/local_process/matcher", rebuilt_path]:
            if os.path.exists(output_path):
                os.remove(output_path)
            run = subprocess.run(
                [executable, input_path, master_path, output_path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
            )
            assert run.returncode == 0, f"{executable} failed on challenge input: {run.stderr}"
            assert os.path.isfile(output_path), f"{executable} did not create its requested output file."
            with open(output_path, "r") as f:
                actual = f.read()
            assert actual == expected, f"{executable} produced incorrect challenge output.\nExpected:\n{expected}\nActual:\n{actual}"


def test_pipeline_executes_matcher_and_processes_new_remote_input():
    paths = [
        "/home/user/remote_in/data.csv",
        "/home/user/master_list.txt",
        "/home/user/local_process/data.csv",
        "/home/user/local_process/processed_data.csv",
        "/home/user/remote_out/processed_data.csv",
    ]
    saved = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            saved[path] = None

    matcher = "/home/user/local_process/matcher"
    temp_dir = tempfile.mkdtemp(prefix="pipeline_verify_")
    real_matcher = os.path.join(temp_dir, "real_matcher")
    marker = os.path.join(temp_dir, "matcher_called")
    token = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
    masters = [f"gamma {token}", f"gimma {token}", "zed", "tiebat", "tiebit"]
    data = (
        f"2001,  GAMMA {token.upper()} \n"
        f"2002, zedd \n"
        f"2003,tiebot\n"
    )
    expected = expected_output(data, masters)

    try:
        os.replace(matcher, real_matcher)
        wrapper = f'''#!/bin/bash
{{
  pwd
  printf '%s\\n' "$@"
}} > {marker!r}
exec {real_matcher!r} "$@"
'''
        with open(matcher, "w") as f:
            f.write(wrapper)
        os.chmod(matcher, 0o755)

        with open("/home/user/remote_in/data.csv", "w") as f:
            f.write(data)
        with open("/home/user/master_list.txt", "w") as f:
            f.write("\n".join(masters) + "\n")
        for path in ["/home/user/local_process/data.csv", "/home/user/local_process/processed_data.csv", "/home/user/remote_out/processed_data.csv"]:
            if os.path.exists(path):
                os.remove(path)

        run = subprocess.run(
            ["/home/user/local_process/pipeline.sh"], cwd="/tmp",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert run.returncode == 0, f"pipeline.sh failed: {run.stderr}"
        assert os.path.isfile(marker), "pipeline.sh did not execute /home/user/local_process/matcher."

        with open(marker, "r") as f:
            call = f.read().splitlines()
        assert len(call) == 4, f"matcher was called with the wrong number of arguments: {call[1:]}"
        call_cwd, arguments = call[0], call[1:]

        def resolved(arg):
            return os.path.realpath(arg if os.path.isabs(arg) else os.path.join(call_cwd, arg))

        required = [
            "/home/user/local_process/data.csv",
            "/home/user/master_list.txt",
            "/home/user/local_process/processed_data.csv",
        ]
        assert [resolved(arg) for arg in arguments] == [os.path.realpath(p) for p in required], \
            f"pipeline passed incorrect matcher arguments: {arguments}"

        with open("/home/user/local_process/data.csv", "r") as f:
            assert f.read() == data, "pipeline did not copy the new remote data.csv into local_process."
        for output_path in ["/home/user/local_process/processed_data.csv", "/home/user/remote_out/processed_data.csv"]:
            assert os.path.isfile(output_path), f"pipeline did not create {output_path}."
            with open(output_path, "r") as f:
                assert f.read() == expected, f"pipeline produced incorrect data in {output_path}."
    finally:
        if os.path.exists(matcher):
            os.remove(matcher)
        if os.path.exists(real_matcher):
            os.replace(real_matcher, matcher)
        shutil.rmtree(temp_dir, ignore_errors=True)
        for path, value in saved.items():
            if value is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                content, mode = value
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(content)
                os.chmod(path, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
