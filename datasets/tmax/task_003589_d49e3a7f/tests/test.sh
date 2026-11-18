#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier-bin

cat << 'WRAPPER_EOF' > /tmp/verifier-bin/gcc
#!/bin/bash
set -e
tool="$(basename "$0")"
real="/usr/bin/$tool"
has_resample=0
no_link=0
out="a.out"
need_out=0

for arg in "$@"; do
    if [ "$need_out" -eq 1 ]; then
        out="$arg"
        need_out=0
        continue
    fi
    case "$arg" in
        resample.c|*/resample.c) has_resample=1 ;;
        -c|-E|-S) no_link=1 ;;
        -o) need_out=1 ;;
        -o*) out="${arg#-o}" ;;
    esac
done

"$real" "$@"

if [ "$has_resample" -eq 1 ] && [ "$no_link" -eq 0 ] && [ -f "$out" ]; then
    echo "compiled" >> /tmp/verifier_c_compiled
    mv -- "$out" "${out}.verifier-real"
    cat > "$out" << 'EXEC_EOF'
#!/bin/bash
echo "executed" >> /tmp/verifier_c_executed
self="$0"
exec -a "$self" "${self}.verifier-real" "$@"
EXEC_EOF
    chmod +x "$out"
fi
WRAPPER_EOF
chmod +x /tmp/verifier-bin/gcc
ln -sf /tmp/verifier-bin/gcc /tmp/verifier-bin/cc

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path

RAW = Path("/home/user/raw_sensors.tsv")
OUTPUT = Path("/home/user/processed_sensors.tsv")
SOURCE = Path("/home/user/resample.c")
SCRIPT = Path("/home/user/run_pipeline.sh")
COMPILED_MARKER = Path("/tmp/verifier_c_compiled")
EXECUTED_MARKER = Path("/tmp/verifier_c_executed")

EXPECTED_ORIGINAL = [
    "NewYork/NYC\t1672531200\t-2.00",
    "Paris/Île-de-France\t1672531200\t5.00",
    "Paris/Île-de-France\t1672534800\t6.00",
    "Paris/Île-de-France\t1672538400\t7.50",
    "Tokyo/東京\t1672531200\t11.00",
    "Tokyo/東京\t1672534800\t11.00",
    "Tokyo/東京\t1672538400\t11.00",
    "Tokyo/東京\t1672534800\t11.00",
    "Tokyo/東京\t1672538400\t11.00",
    "Tokyo/東京\t1672542000\t9.00",
]
# Preserve the original verifier's actual expected value (without duplicate lines).
EXPECTED_ORIGINAL = [
    "NewYork/NYC\t1672531200\t-2.00",
    "Paris/Île-de-France\t1672531200\t5.00",
    "Paris/Île-de-France\t1672534800\t6.00",
    "Paris/Île-de-France\t1672538400\t7.50",
    "Tokyo/東京\t1672531200\t11.00",
    "Tokyo/東京\t1672534800\t11.00",
    "Tokyo/東京\t1672538400\t11.00",
    "Tokyo/東京\t1672542000\t9.00",
]


def test_files_exist():
    assert SOURCE.exists(), "/home/user/resample.c is missing."
    assert SCRIPT.exists(), "/home/user/run_pipeline.sh is missing."
    assert OUTPUT.exists(), "/home/user/processed_sensors.tsv is missing."


def test_processed_sensors_content():
    with OUTPUT.open("r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == EXPECTED_ORIGINAL, (
        f"Contents of {OUTPUT} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(EXPECTED_ORIGINAL)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def derive_expected(rows):
    grouped = {}
    for timestamp, location, temperature, status in rows:
        if status != "OK":
            continue
        hour = (timestamp // 3600) * 3600
        grouped.setdefault(location, {}).setdefault(hour, []).append(float(temperature))

    result = []
    for location in sorted(grouped, key=lambda value: value.encode("utf-8")):
        hourly = grouped[location]
        averages = {hour: sum(values) / len(values) for hour, values in hourly.items()}
        first, last = min(averages), max(averages)
        previous = None
        for hour in range(first, last + 1, 3600):
            if hour in averages:
                previous = averages[hour]
            result.append(f"{location}\t{hour}\t{previous:.2f}")
    return result


def test_pipeline_executes_c_and_handles_unseen_input():
    original_raw = RAW.read_bytes()
    original_output = OUTPUT.read_bytes()
    token = secrets.token_hex(5)
    base = random.SystemRandom().randrange(500000, 900000) * 3600
    rng = random.SystemRandom()

    locations = [
        f"Alpha/é-{token}",
        f"Tokyo/東京-{token}",
        f"!North-{token}",
    ]
    a, b, c, d, e, f = [rng.randrange(-30, 41) for _ in range(6)]
    rows = [
        (base + 17, locations[0], str(a), "OK"),
        (base + 1800, locations[0], str(b), "OK"),
        (base + 2 * 3600 + 11, locations[0], str(c), "OK"),
        (base + 3600 + 25, locations[0], "999", "ERR: low battery"),
        (base + 3600 + 40, locations[1], str(d), "OK"),
        (base + 3600 + 50, locations[1], "888", "OK "),
        (base + 73, locations[2], str(e), "OK"),
        (base + 3 * 3600 + 19, locations[2], str(f), "OK"),
        (base + 2 * 3600, locations[2], "777", "ERR"),
    ]
    rng.shuffle(rows)
    raw_text = "".join(
        f"{timestamp}\t{location}\t{temperature}\t{status}\n"
        for timestamp, location, temperature, status in rows
    )
    expected = derive_expected(rows)

    try:
        RAW.write_text(raw_text, encoding="utf-8")
        OUTPUT.unlink(missing_ok=True)
        COMPILED_MARKER.unlink(missing_ok=True)
        EXECUTED_MARKER.unlink(missing_ok=True)

        env = os.environ.copy()
        env["PATH"] = "/tmp/verifier-bin:" + env.get("PATH", "")
        completed = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert completed.returncode == 0, (
            "run_pipeline.sh failed on an unseen input.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert COMPILED_MARKER.exists(), (
            "run_pipeline.sh did not compile /home/user/resample.c with cc or gcc."
        )
        assert EXECUTED_MARKER.exists(), (
            "run_pipeline.sh compiled resample.c but did not execute the resulting program."
        )
        assert OUTPUT.exists(), "The pipeline did not create processed_sensors.tsv."
        actual = OUTPUT.read_text(encoding="utf-8").splitlines()
        assert actual == expected, (
            "Pipeline output for an unseen input was incorrect.\n"
            f"Expected:\n{chr(10).join(expected)}\n"
            f"Actual:\n{chr(10).join(actual)}"
        )
    finally:
        RAW.write_bytes(original_raw)
        OUTPUT.write_bytes(original_output)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
