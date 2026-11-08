#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def run_analyzer(capture_path):
    result = subprocess.run(
        ["python3", "/home/user/analyze.py", capture_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Script execution failed with error: {result.stderr}"
    return result.stdout.strip()


def test_ticket_resolution_content():
    """Verify that ticket_resolution.txt contains the correct IP and byte count."""
    path = "/home/user/ticket_resolution.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you save the output?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "10.0.0.99,5600"
    assert content == expected, f"Expected '{expected}' in {path}, but got '{content}'."


def test_analyze_script_fixed():
    """Verify that the analyze.py script has been fixed and produces the correct output."""
    script_path = "/home/user/analyze.py"
    capture_path = "/home/user/network_capture.txt"

    assert os.path.isfile(script_path), f"File {script_path} is missing."
    assert os.path.isfile(capture_path), f"File {capture_path} is missing."

    output = run_analyzer(capture_path)
    expected = "10.0.0.99,5600"
    assert output == expected, f"Expected script to output '{expected}', but got '{output}'. The off-by-one error may not be fully fixed."


def make_ip(used):
    while True:
        ip = f"10.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}"
        if ip not in used:
            used.add(ip)
            return ip


def write_capture(path, records):
    with open(path, "w") as f:
        for index, (destination, length) in enumerate(records, 1):
            f.write(
                f"12:00:{index:02d}.000 IP 192.168.50.7.5000 > "
                f"{destination}.443: Flags [.], seq {index}, ack 1, win 256, length {length}\n"
            )


def expected_for(records):
    totals = {}
    for destination, length in records:
        totals[destination] = totals.get(destination, 0) + length
    top = max(totals, key=totals.get)
    return f"{top},{totals[top]}"


def test_analyzer_handles_unseen_captures_and_last_line():
    """Exercise real aggregation with unpredictable values, including a decisive final packet."""
    used = set()
    ip_a = make_ip(used)
    ip_b = make_ip(used)
    ip_c = make_ip(used)
    ip_d = make_ip(used)
    base = 500 + secrets.randbelow(1500)

    # The last record changes the winner, so skipping len(lines)-1 gives the wrong answer.
    decisive_final = [
        (ip_a, base + 100),
        (ip_b, 100 + secrets.randbelow(100)),
        (ip_a, base + 200),
        (ip_b, 2 * base + 500),
    ]

    # The winner is aggregated across earlier records and is not simply the last destination.
    aggregate_case = [
        (ip_d, base // 2),
        (ip_c, base + 1000),
        (ip_c, base + 900),
        (ip_d, 50 + secrets.randbelow(50)),
    ]

    with tempfile.TemporaryDirectory() as directory:
        for index, records in enumerate((decisive_final, aggregate_case)):
            capture = os.path.join(directory, f"capture_{index}.txt")
            write_capture(capture, records)
            expected = expected_for(records)
            output = run_analyzer(capture)
            assert output == expected, f"Expected '{expected}' for generated capture, but got '{output}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
