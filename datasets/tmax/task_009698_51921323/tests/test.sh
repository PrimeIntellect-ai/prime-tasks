#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def test_output_file_exists_and_content():
    output_file = "/home/user/loc_summary.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Did you run the Rust script?"

    expected_content = """hour_bucket,loc_key,unique_masked_ips,avg_conf
3600,BTN_CANCEL,1,95
3600,BTN_OK,2,85
7200,BTN_OK,2,95"""

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {output_file} does not match expected output.\nExpected:\n{expected_content}\nGot:\n{content}"


def test_rust_script_exists():
    script_file = "/home/user/etl_fix.rs"
    assert os.path.isfile(script_file), f"Rust script {script_file} is missing."


def expected_summary(rows):
    deduplicated = set(rows)
    groups = {}

    for ts, ip, loc_key, conf in deduplicated:
        hour_bucket = (ts // 3600) * 3600
        masked_ip = ip.rsplit(".", 1)[0] + ".0"
        group = groups.setdefault((hour_bucket, loc_key), {"ips": set(), "conf": []})
        group["ips"].add(masked_ip)
        group["conf"].append(conf)

    lines = ["hour_bucket,loc_key,unique_masked_ips,avg_conf"]
    for (hour_bucket, loc_key), values in sorted(groups.items()):
        avg_conf = sum(values["conf"]) // len(values["conf"])
        lines.append(f"{hour_bucket},{loc_key},{len(values['ips'])},{avg_conf}")
    return "\n".join(lines)


def make_fixture(seed):
    rng = random.Random(seed)
    base_hour = rng.randint(20, 200) * 3600
    suffix = f"{seed:016x}"
    key_a = "KEY_A_" + suffix
    key_b = "KEY_B_" + suffix

    rows = [
        (base_hour, "10.20.30.1", key_a, 11),
        (base_hour + 3599, "10.20.30.254", key_a, 92),
        (base_hour + 17, "10.20.31.8", key_a, 48),
        (base_hour + 1800, "172.16.4.9", key_b, 77),
        (base_hour + 3600, "172.16.4.100", key_a, 39),
        (base_hour + 7205, "192.168.7.3", key_b, 100),
    ]

    for _ in range(30):
        hour_offset = rng.choice([0, 1, 2, 4])
        ts = base_hour + hour_offset * 3600 + rng.randrange(3600)
        ip = f"{rng.randrange(1, 224)}.{rng.randrange(256)}.{rng.randrange(8)}.{rng.randrange(1, 255)}"
        loc_key = rng.choice([key_a, key_b, "KEY_C_" + suffix])
        conf = rng.randrange(0, 101)
        rows.append((ts, ip, loc_key, conf))

    # Add exact retry duplicates in non-adjacent positions.
    rows.extend([rows[0], rows[2], rows[8], rows[0], rows[-3]])
    rng.shuffle(rows)
    return rows


def test_compile_and_execute_rust_script_on_unseen_inputs():
    source = "/home/user/etl_fix.rs"
    executable = "/tmp/etl_fix_submission"
    input_file = "/home/user/raw_loc_events.csv"
    output_file = "/home/user/loc_summary.csv"

    with open(input_file, "rb") as f:
        original_input = f.read()
    with open(output_file, "rb") as f:
        original_output = f.read()

    try:
        compile_result = subprocess.run(
            ["rustc", source, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"Rust script failed to compile:\n{compile_result.stderr}"
        assert os.path.isfile(executable), "rustc did not produce an executable"

        for _ in range(2):
            seed = int.from_bytes(os.urandom(8), "big")
            rows = make_fixture(seed)
            with open(input_file, "w", newline="") as f:
                f.write("ts,ip,loc_key,conf\n")
                for ts, ip, loc_key, conf in rows:
                    f.write(f"{ts},{ip},{loc_key},{conf}\n")

            if os.path.exists(output_file):
                os.remove(output_file)

            run_result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert run_result.returncode == 0, f"Compiled ETL script failed:\n{run_result.stderr}"
            assert os.path.isfile(output_file), "Compiled ETL script did not create /home/user/loc_summary.csv"

            with open(output_file, "r") as f:
                actual = f.read().strip()
            expected = expected_summary(rows)
            assert actual == expected, f"ETL output for an unseen input was incorrect.\nExpected:\n{expected}\nGot:\n{actual}"
    finally:
        with open(input_file, "wb") as f:
            f.write(original_input)
        with open(output_file, "wb") as f:
            f.write(original_output)
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
