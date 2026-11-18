#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

BASE = "/home/user/perf_test"


def run_checked(command, *, input_text=None, timeout=20):
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def parse_crunch_log(path):
    starts = {}
    completed = []
    start_re = re.compile(r"^\[(\d+)\] START ID:(\d+)$")
    end_re = re.compile(r"^\[(\d+)\] END ID:(\d+) RESULT:(-?\d+(?:\.\d+)?)$")

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    for line in lines:
        match = start_re.fullmatch(line)
        if match:
            timestamp, payload_id = map(int, match.groups())
            assert payload_id not in starts, f"Duplicate START for ID {payload_id}"
            starts[payload_id] = timestamp
            continue

        match = end_re.fullmatch(line)
        assert match, f"Malformed crunch.log line: {line!r}"
        timestamp = int(match.group(1))
        payload_id = int(match.group(2))
        result = float(match.group(3))
        assert payload_id in starts, f"END without START for ID {payload_id}"
        assert timestamp >= starts[payload_id], f"Negative duration for ID {payload_id}"
        completed.append((payload_id, timestamp - starts.pop(payload_id), result))

    assert not starts, f"Missing END records for IDs: {sorted(starts)}"
    return completed


@pytest.fixture(scope="session", autouse=True)
def execute_artifacts():
    build_script = os.path.join(BASE, "build.sh")
    binary = os.path.join(BASE, "cruncher")
    crunch_log = os.path.join(BASE, "crunch.log")
    gen_log = os.path.join(BASE, "gen.log")

    assert os.path.isfile(build_script), "build.sh is missing."
    with open(build_script, "r") as f:
        build_content = f.read()
    assert "-lm" in build_content, "The build.sh script does not contain the required '-lm' flag."

    # Require build.sh itself to produce a fresh, runnable native binary.
    if os.path.lexists(binary):
        os.remove(binary)
    run_checked(["/bin/bash", build_script], timeout=20)
    assert os.path.isfile(binary), "The cruncher binary was not built."
    assert os.access(binary, os.X_OK), "The cruncher binary is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cruncher must be a compiled ELF executable."

    # Exercise the cruncher directly on controlled input and derive the slow ID
    # from the timestamps it actually writes.
    if os.path.exists(crunch_log):
        os.remove(crunch_log)
    run_checked([binary], input_text="85 7225\n84 7056\n83 6889\n", timeout=10)
    controlled = parse_crunch_log(crunch_log)
    assert [item[0] for item in controlled] == [85, 84, 83]
    assert [item[2] for item in controlled] == pytest.approx([85.0, 84.0, 83.0], abs=0.01)
    controlled_slow = [payload_id for payload_id, duration, _ in controlled if duration > 1000]
    assert controlled_slow == [84], f"Controlled execution produced slow IDs {controlled_slow}"
    assert all(duration < 1000 for payload_id, duration, _ in controlled if payload_id != 84)

    # Run the requested master pipeline, rather than accepting pre-created logs.
    for path in (crunch_log, gen_log):
        if os.path.exists(path):
            os.remove(path)
    run_checked(["/bin/bash", os.path.join(BASE, "run_pipeline.sh")], timeout=20)

    assert os.path.isfile(gen_log), "run_pipeline.sh did not generate gen.log."
    assert os.path.isfile(crunch_log), "run_pipeline.sh did not generate crunch.log."

    generated = []
    gen_re = re.compile(r"^\[(\d+)\] GENERATED ID:(\d+)$")
    with open(gen_log, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            match = gen_re.fullmatch(line)
            assert match, f"Malformed gen.log line: {line!r}"
            generated.append(int(match.group(2)))
    assert generated == list(range(80, 91)), f"Unexpected generated IDs: {generated}"

    pipeline = parse_crunch_log(crunch_log)
    assert [item[0] for item in pipeline] == list(range(80, 91))
    for payload_id, _, result in pipeline:
        assert result == pytest.approx(float(payload_id), abs=0.01)

    slow_ids = [payload_id for payload_id, duration, _ in pipeline if duration > 1000]
    assert slow_ids == [84], f"Pipeline log produced slow IDs {slow_ids}"
    assert all(duration < 1000 for payload_id, duration, _ in pipeline if payload_id != 84)

    pytest.pipeline_slow_id = slow_ids[0]


def test_solution_file_exists():
    assert os.path.isfile("/home/user/solution.txt"), "The file /home/user/solution.txt does not exist."


def test_solution_file_content():
    with open("/home/user/solution.txt", "r") as f:
        content = f.read().strip().split('\n')

    assert len(content) == 2, "The solution.txt file must contain exactly two lines."

    flag_line = content[0].strip()
    id_line = content[1].strip()

    assert flag_line == "Flag: -lm", f"Expected 'Flag: -lm', but got '{flag_line}'"
    assert id_line == "Bottleneck ID: 84", f"Expected 'Bottleneck ID: 84', but got '{id_line}'"
    assert id_line == f"Bottleneck ID: {pytest.pipeline_slow_id}"


def test_build_script_fixed():
    assert os.path.isfile("/home/user/perf_test/build.sh"), "build.sh is missing."
    with open("/home/user/perf_test/build.sh", "r") as f:
        content = f.read()
    assert "-lm" in content, "The build.sh script does not contain the required '-lm' flag."


def test_cruncher_binary_exists():
    assert os.path.isfile("/home/user/perf_test/cruncher"), "The cruncher binary was not built."
    assert os.access("/home/user/perf_test/cruncher", os.X_OK), "The cruncher binary is not executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
