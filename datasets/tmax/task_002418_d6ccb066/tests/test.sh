#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import shlex
import shutil
import stat
import subprocess
import tempfile


def test_fuzz_script_exists_and_executable():
    path = '/home/user/fuzz.sh'
    assert os.path.isfile(path), f"Fuzzing script {path} does not exist."

    st = os.stat(path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"Fuzzing script {path} is not executable."


def test_final_timeline_log():
    path = '/home/user/final_timeline.log'
    assert os.path.isfile(path), f"Final timeline log {path} does not exist."

    expected_lines = [
        "1672531200 [INFO] Service A started",
        "1672531202 [INFO] Service B started",
        "1672531205 [DEBUG] Connecting to DB",
        "1672531210 [WARN] High memory usage",
        "1672531215 [INFO] DB connected",
        "1672531220 [INFO] Shutdown"
    ]

    with open(path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {path} do not match the expected merged output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def run_merge(path, left_lines, right_lines):
    with tempfile.TemporaryDirectory() as td:
        left = os.path.join(td, 'left.log')
        right = os.path.join(td, 'right.log')
        with open(left, 'w') as f:
            if left_lines:
                f.write('\n'.join(left_lines) + '\n')
        with open(right, 'w') as f:
            if right_lines:
                f.write('\n'.join(right_lines) + '\n')

        result = subprocess.run(
            [path, left, right], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"{path} exited {result.returncode} for input lengths "
            f"{len(left_lines)} and {len(right_lines)}. stderr: {result.stderr}"
        )
        return result.stdout.splitlines()


def test_merge_timeline_script_fixed():
    path = '/home/user/merge_timeline.sh'
    assert os.path.isfile(path), f"Script {path} does not exist."

    # Preserve the original empty-input boundary assertion.
    assert run_merge(path, [], []) == []

    # Exercise varying and asymmetric lengths with verifier-generated contents.
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = {(0, n) for n in range(11)} | {(n, 0) for n in range(11)}
    cases |= {(n, n) for n in range(11)}
    cases |= {(rng.randrange(11), rng.randrange(11)) for _ in range(15)}

    for case_number, (left_count, right_count) in enumerate(sorted(cases)):
        total = left_count + right_count
        timestamps = rng.sample(range(1000000000, 2000000000), total)
        rng.shuffle(timestamps)
        left = [
            f"{timestamps[i]} [TEST] left-{case_number}-{i}-{rng.getrandbits(48):012x}"
            for i in range(left_count)
        ]
        right = [
            f"{timestamps[left_count + i]} [TEST] right-{case_number}-{i}-{rng.getrandbits(48):012x}"
            for i in range(right_count)
        ]

        output = run_merge(path, left, right)
        supplied = left + right
        assert collections.Counter(output) == collections.Counter(supplied), (
            f"Merge lost, duplicated, or changed entries for lengths "
            f"{left_count} and {right_count}."
        )
        output_timestamps = [int(line.split(None, 1)[0]) for line in output]
        assert output_timestamps == sorted(output_timestamps), (
            f"Merge output is not numerically ordered for lengths "
            f"{left_count} and {right_count}."
        )


def test_fuzzer_generates_and_submits_varied_inputs():
    fuzz_path = '/home/user/fuzz.sh'
    merge_path = '/home/user/merge_timeline.sh'

    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, 'merge_timeline.backup')
        probe_log = os.path.join(td, 'probe.log')
        shutil.copy2(merge_path, backup)

        probe = (
            "#!/bin/bash\n"
            "if [ \"$#\" -ne 2 ] || [ ! -f \"$1\" ] || [ ! -f \"$2\" ]; then\n"
            f"  echo BAD >> {shlex.quote(probe_log)}\n"
            "  exit 2\n"
            "fi\n"
            "c1=$(wc -l < \"$1\")\n"
            "c2=$(wc -l < \"$2\")\n"
            f"printf '%s %s\\n' \"$c1\" \"$c2\" >> {shlex.quote(probe_log)}\n"
            "exit 0\n"
        )

        try:
            with open(merge_path, 'w') as f:
                f.write(probe)
            os.chmod(merge_path, 0o755)

            result = subprocess.run(
                [fuzz_path], cwd=td, capture_output=True, text=True, timeout=30
            )
            assert result.returncode == 0, (
                f"Fuzzer exited with {result.returncode}. stderr: {result.stderr}"
            )
            assert os.path.isfile(probe_log), "Fuzzer never invoked merge_timeline.sh."
            with open(probe_log) as f:
                records = [line.strip() for line in f if line.strip()]

            assert 'BAD' not in records, "Fuzzer invoked merge_timeline.sh without two valid log files."
            assert len(records) >= 3, "Fuzzer did not test multiple generated input lengths."
            pairs = [tuple(map(int, record.split())) for record in records]
            observed_lengths = {length for pair in pairs for length in pair}
            assert 0 in observed_lengths, "Fuzzer did not exercise an empty-log boundary."
            assert any(length > 0 for length in observed_lengths), "Fuzzer only exercised empty logs."
            assert len(observed_lengths) >= 3, "Fuzzer did not generate a useful variety of log lengths."
        finally:
            if os.path.lexists(merge_path):
                os.remove(merge_path)
            os.replace(backup, merge_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
