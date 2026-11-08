#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
from decimal import Decimal

PCAP = "/home/user/telemetry.pcap"
LOGS = "/home/user/extracted_logs.txt"
SCRIPT = "/home/user/process_telemetry.sh"
REPORT = "/home/user/final_report.txt"
EXPECTED_LATENCIES = ["12.3456", "98.7654", "45.6789", "10.0001", "5.5555"]


def pcap_latency_lines():
    result = subprocess.run(
        ["/usr/bin/tshark", "-r", PCAP, "-Y", "udp.dstport == 8080", "-T", "fields", "-e", "udp.payload"],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, f"tshark failed to parse the PCAP: {result.stderr}"

    lines = []
    for encoded in result.stdout.splitlines():
        encoded = encoded.strip().replace(":", "")
        if not encoded:
            continue
        try:
            payload = bytes.fromhex(encoded).decode("ascii")
        except (ValueError, UnicodeDecodeError) as exc:
            raise AssertionError(f"Invalid UDP payload returned by tshark: {encoded!r}") from exc
        for line in payload.splitlines():
            if re.fullmatch(r"LATENCY=[0-9]+(?:\.[0-9]+)?", line):
                lines.append(line)
    return lines


def run_script(input_path):
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    env = os.environ.copy()
    env["PATH"] = "/usr/bin:/bin"
    result = subprocess.run(
        [SCRIPT, input_path],
        text=True,
        capture_output=True,
        env=env,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"process_telemetry.sh failed with exit code {result.returncode}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(REPORT), f"Expected final report file {REPORT} is missing."
    with open(REPORT, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def test_complete_pipeline_and_script_behavior(tmp_path):
    assert os.path.isfile(PCAP), f"Expected PCAP {PCAP} is missing."
    assert os.path.isfile(LOGS), f"Expected extracted logs file {LOGS} is missing."
    assert os.path.isfile(SCRIPT), f"Expected Bash script {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), "process_telemetry.sh must be an actual repaired script, not a symlink."
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, "process_telemetry.sh is not executable."

    with open(SCRIPT, "r", encoding="utf-8") as handle:
        script_text = handle.read()
    first_line = script_text.splitlines()[0] if script_text.splitlines() else ""
    assert re.match(r"^#!\s*/(?:usr/)?bin/(?:env\s+)?bash\b", first_line), (
        "process_telemetry.sh must remain a Bash script."
    )
    executable_text = "\n".join(
        line for line in script_text.splitlines() if not line.lstrip().startswith("#")
    )
    assert not re.search(r"\b(?:python(?:[0-9.]+)?|perl)\b", executable_text, re.IGNORECASE), (
        "The Bash pipeline may not be bypassed with Python or Perl."
    )

    expected_lines = pcap_latency_lines()
    assert expected_lines == [f"LATENCY={value}" for value in EXPECTED_LATENCIES], (
        "The supplied PCAP does not contain the expected UDP telemetry stream."
    )

    with open(LOGS, "r", encoding="utf-8") as handle:
        extracted_lines = [line.strip() for line in handle if line.strip()]

    # Preserve the original fixed-value assertions.
    content = "\n".join(extracted_lines)
    for value in EXPECTED_LATENCIES:
        assert value in content, f"Expected latency value {value} not found in {LOGS}."

    # Also require the extraction to exactly match the UDP/8080 payloads in the PCAP.
    assert extracted_lines == expected_lines, (
        "extracted_logs.txt does not exactly match the LATENCY lines parsed from UDP port 8080."
    )

    original_output = run_script(LOGS)
    assert original_output == "Average Latency: 34.4691", (
        f"Final report content is incorrect: {original_output!r}"
    )

    # Exercise the repaired script on unpredictable values so a fabricated fixed report cannot pass.
    rng = random.SystemRandom()
    count = 5
    units = [rng.randrange(10000, 900000) for _ in range(count)]
    units[-1] += (-sum(units)) % count
    dynamic_log = tmp_path / "telemetry_input.txt"
    dynamic_log.write_text(
        "header ignored\n"
        + "\n".join(f"LATENCY={value // 10000}.{value % 10000:04d}" for value in units)
        + "\ntrailer ignored\n",
        encoding="utf-8",
    )
    expected_average = Decimal(sum(units)) / Decimal(count) / Decimal(10000)
    expected_dynamic = f"Average Latency: {expected_average:.4f}"
    assert run_script(str(dynamic_log)) == expected_dynamic

    # Leave and re-check the requested final report generated from extracted_logs.txt.
    assert run_script(LOGS) == "Average Latency: 34.4691"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
