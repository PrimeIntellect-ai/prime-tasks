#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import stat
import subprocess
import tempfile


def expected_from_lines(lines):
    buckets = {}
    for line in lines:
        line = line.strip()
        if not line:
            continue

        m = re.match(r'^\[(\d+)\]\s+([^=]+)=([^\s]+)\s+(.*)$', line)
        assert m, f"Failed to parse raw log line: {line}"

        epoch = int(m.group(1))
        key = m.group(2)
        value = m.group(3)
        ip = m.group(4)
        window = (epoch // 3600) * 3600

        ip_parts = ip.split('.')
        ip_parts[-1] = 'XXX'
        masked_ip = '.'.join(ip_parts)

        dict_key = (window, key)
        if dict_key not in buckets or buckets[dict_key][0] < epoch:
            buckets[dict_key] = (epoch, value, masked_ip)

    expected_lines = []
    for (window, key), (_, value, masked_ip) in buckets.items():
        expected_lines.append(f"{window},{key},{value},{masked_ip}")
    expected_lines.sort(key=lambda x: (int(x.split(',')[0]), x.split(',')[1]))
    return expected_lines


def test_pipeline_files_exist():
    assert os.path.exists("/home/user/process_logs.c"), "/home/user/process_logs.c is missing."
    assert os.path.isfile("/home/user/process_logs.c"), "/home/user/process_logs.c is not a regular file."
    assert os.path.exists("/home/user/run_pipeline.sh"), "/home/user/run_pipeline.sh is missing."
    assert os.path.isfile("/home/user/run_pipeline.sh"), "/home/user/run_pipeline.sh is not a regular file."
    assert os.access("/home/user/run_pipeline.sh", os.X_OK), "/home/user/run_pipeline.sh is not executable."


def test_pipeline_execution_and_output():
    result = subprocess.run(
        ["/home/user/run_pipeline.sh"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"run_pipeline.sh failed to execute. Stderr: {result.stderr}"

    csv_file = "/home/user/processed_logs.csv"
    assert os.path.exists(csv_file), f"{csv_file} was not created by the pipeline."

    raw_file = "/home/user/raw_config_logs.txt"
    assert os.path.exists(raw_file), f"{raw_file} is missing."
    with open(raw_file, "r") as f:
        expected_lines = expected_from_lines(f.readlines())
    expected_csv = "\n".join(expected_lines)

    with open(csv_file, "r") as f:
        actual_csv = f.read().strip()

    assert actual_csv == expected_csv, (
        f"Contents of {csv_file} do not match the expected output.\n"
        f"Expected:\n{expected_csv}\n\nActual:\n{actual_csv}"
    )


def test_c_program_on_additional_generated_input():
    source = "/home/user/process_logs.c"
    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "process_logs_test")
        compiled = subprocess.run(
            ["gcc", source, "-o", executable],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"process_logs.c did not compile:\n{compiled.stderr}"

        rng = random.Random(secrets.randbits(128))
        lines = []
        first_window = rng.randint(250000, 650000) * 3600
        keys = ["ALPHA", "CACHE_LIMIT", "FEATURE_BETA", "RETRY_COUNT", "ZETA_MODE"]
        for window_index in range(4):
            window = first_window + window_index * 3600
            for key_index, key in enumerate(keys):
                offsets = rng.sample(range(1, 3599), 3)
                for record_index, offset in enumerate(offsets):
                    epoch = window + offset
                    value = f"v{window_index}_{key_index}_{record_index}_{rng.randint(1000,9999)}"
                    ip = f"{10 + window_index}.{20 + key_index}.{rng.randint(0,255)}.{rng.randint(1,254)}"
                    lines.append(f"[{epoch}] {key}={value} {ip}")

        # Include adjacent-window boundary records and repeated keys explicitly.
        boundary = first_window + 4 * 3600
        lines.extend([
            f"[{boundary - 1}] EDGE_KEY=before 203.0.113.9",
            f"[{boundary}] EDGE_KEY=at_boundary 203.0.113.10",
            f"[{boundary + 1}] EDGE_KEY=after_boundary 203.0.113.11",
            f"[{boundary + 3599}] EDGE_KEY=latest 203.0.113.12",
        ])
        rng.shuffle(lines)
        input_text = "\n".join(lines) + "\n"

        result = subprocess.run(
            [executable],
            input=input_text,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"Compiled process_logs failed. Stderr: {result.stderr}"

        actual_lines = result.stdout.strip().splitlines() if result.stdout.strip() else []
        actual_lines.sort(key=lambda x: (int(x.split(',')[0]), x.split(',')[1]))
        expected_lines = expected_from_lines(lines)
        assert actual_lines == expected_lines, (
            "process_logs.c produced incorrect output on additional input.\n"
            f"Expected:\n{chr(10).join(expected_lines)}\n\n"
            f"Actual:\n{chr(10).join(actual_lines)}"
        )


def test_script_compiles_and_uses_source_and_stdin():
    source_path = "/home/user/process_logs.c"
    raw_path = "/home/user/raw_config_logs.txt"
    script_path = "/home/user/run_pipeline.sh"
    executable_path = "/home/user/process_logs"

    with open(source_path, "rb") as f:
        original_source = f.read()
    with open(raw_path, "rb") as f:
        original_raw = f.read()
    source_mode = stat.S_IMODE(os.stat(source_path).st_mode)
    raw_mode = stat.S_IMODE(os.stat(raw_path).st_mode)

    probe_source = r'''#include <stdio.h>
#include <string.h>
int main(void) {
    char line[512];
    int count = 0, saw_a = 0, saw_b = 0;
    while (fgets(line, sizeof(line), stdin)) {
        count++;
        if (strstr(line, "PIPE_PROBE_A=one")) saw_a = 1;
        if (strstr(line, "PIPE_PROBE_B=two")) saw_b = 1;
    }
    if (count != 2 || !saw_a || !saw_b) return 23;
    puts("7200,Z_PROBE,last,198.51.100.XXX");
    puts("3600,A_PROBE,first,203.0.113.XXX");
    return 0;
}
'''
    probe_raw = (
        "[5001] PIPE_PROBE_A=one 192.0.2.44\n"
        "[9001] PIPE_PROBE_B=two 192.0.2.45\n"
    )
    expected = (
        "3600,A_PROBE,first,203.0.113.XXX\n"
        "7200,Z_PROBE,last,198.51.100.XXX"
    )

    try:
        with open(source_path, "w") as f:
            f.write(probe_source)
        with open(raw_path, "w") as f:
            f.write(probe_raw)
        if os.path.lexists(executable_path):
            os.remove(executable_path)

        result = subprocess.run(
            [script_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            "run_pipeline.sh failed when required to compile and run process_logs.c. "
            f"Stderr: {result.stderr}"
        )
        assert os.path.isfile(executable_path), "run_pipeline.sh did not create /home/user/process_logs"
        with open("/home/user/processed_logs.csv", "r") as f:
            actual = f.read().strip()
        assert actual == expected, (
            "run_pipeline.sh did not compile/use process_logs.c, pipe the raw file to it, "
            "and sort its output correctly.\n"
            f"Expected:\n{expected}\n\nActual:\n{actual}"
        )
    finally:
        with open(source_path, "wb") as f:
            f.write(original_source)
        os.chmod(source_path, source_mode)
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        os.chmod(raw_path, raw_mode)
        # Restore the real executable and final CSV after the orchestration probe.
        subprocess.run([script_path], cwd="/home/user", capture_output=True, timeout=20)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
