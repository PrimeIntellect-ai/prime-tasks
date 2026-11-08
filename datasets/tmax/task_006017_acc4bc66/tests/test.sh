#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

from scapy.all import rdpcap, wrpcap

EXPECTED_MONITOR = '''#!/bin/bash
source /home/user/env.sh
declare -A PACKET_CACHE
TOTAL_BYTES=0

while read -r line; do
    if echo "$line" | grep -q "IP "; then
        len=$(echo "$line" | grep -oP 'length \\K[0-9]+' || echo "")
        src_ip=$(echo "$line" | awk '{print $2}' | cut -d. -f1-4)

        # Cache packet data
        PACKET_CACHE["${#PACKET_CACHE[@]}"]="$line"

        if [[ -n "$len" ]]; then
            TOTAL_BYTES=$((TOTAL_BYTES + len))
        fi

        if (( TOTAL_BYTES > CLEANUP_THRESHOLD )); then
            unset PACKET_CACHE
            declare -A PACKET_CACHE
            TOTAL_BYTES=0
        fi
    fi
done < <(tcpdump -nn -r "$1" 2>/dev/null)
'''


def get_expected_results():
    """Calculate the expected result using the system tcpdump."""
    cmd = ["/usr/sbin/tcpdump", "-nn", "-r", "/home/user/traffic.pcap"]
    result = subprocess.run(cmd, capture_output=True, text=True)

    ip_totals = {}
    for line in result.stdout.splitlines():
        if "IP " in line:
            parts = line.split()
            try:
                ip_idx = parts.index("IP")
                src_ip_port = parts[ip_idx + 1]
                src_ip = ".".join(src_ip_port.split(".")[:4])

                if "length" in parts:
                    len_idx = parts.index("length")
                    length_str = parts[len_idx + 1].strip(":,")
                    length = int(length_str)
                    ip_totals[src_ip] = ip_totals.get(src_ip, 0) + length
            except (ValueError, IndexError):
                continue

    if not ip_totals:
        return "10.0.0.5", 272

    top_ip = max(ip_totals, key=ip_totals.get)
    return top_ip, ip_totals[top_ip]


def test_report_content_correct():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Missing {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert len(lines) >= 3, f"Report file {report_path} must have at least 3 lines. Found {len(lines)} lines."
    assert lines[0] == "PACKET_CACHE", f"Line 1 (leaking array name) is incorrect. Expected 'PACKET_CACHE', got '{lines[0]}'"

    expected_ip, expected_bytes = get_expected_results()
    assert lines[1] == expected_ip, f"Line 2 (top source IP) is incorrect. Expected '{expected_ip}', got '{lines[1]}'"
    assert lines[2] == str(expected_bytes), f"Line 3 (total bytes for top IP) is incorrect. Expected '{expected_bytes}', got '{lines[2]}'"


def test_monitor_unmodified():
    monitor_path = "/home/user/monitor.sh"
    assert os.path.isfile(monitor_path), f"Missing {monitor_path}"
    with open(monitor_path, "rb") as f:
        actual = f.read()
    assert actual == EXPECTED_MONITOR.encode(), "/home/user/monitor.sh was modified"


def test_environment_fixed():
    env_path = "/home/user/env.sh"
    assert os.path.isfile(env_path), f"Missing {env_path}"

    # Preserve the original assertion that the conflicting executable is not selected.
    cmd = ["bash", "-c", f"source {env_path} && which tcpdump"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    resolved_tcpdump = result.stdout.strip()
    assert "/home/user/bad_bin/tcpdump" not in resolved_tcpdump, (
        "The environment misconfiguration is not fixed. "
        "`which tcpdump` still resolves to the malicious mock intercepting the length field."
    )

    # An empty or broken PATH must not pass: tcpdump must resolve successfully to
    # the installed system implementation and produce numeric length fields.
    assert result.returncode == 0, "tcpdump cannot be resolved after sourcing env.sh"
    assert resolved_tcpdump, "tcpdump resolution returned no executable"
    assert os.path.isfile(resolved_tcpdump), f"Resolved tcpdump does not exist: {resolved_tcpdump}"
    assert os.access(resolved_tcpdump, os.X_OK), f"Resolved tcpdump is not executable: {resolved_tcpdump}"
    assert os.path.samefile(resolved_tcpdump, "/usr/sbin/tcpdump"), (
        f"tcpdump must resolve to the system implementation, not {resolved_tcpdump}"
    )

    run = subprocess.run(
        ["bash", "-c", 'source "$1" && tcpdump -nn -r /home/user/traffic.pcap', "bash", env_path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert run.returncode == 0, f"tcpdump failed under the repaired environment: {run.stderr}"
    assert re.search(r"\\blength [0-9]+\\b", run.stdout), (
        "tcpdump output under the repaired environment does not contain numeric packet lengths"
    )


def test_monitor_cleanup_runs_with_repaired_environment(tmp_path):
    packets = list(rdpcap("/home/user/traffic.pcap"))
    assert packets, "traffic.pcap contains no packets"
    exercise_pcap = tmp_path / "cleanup-exercise.pcap"
    wrpcap(str(exercise_pcap), packets * 4)

    result = subprocess.run(
        ["bash", "-x", "/home/user/monitor.sh", str(exercise_pcap)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"monitor.sh failed under the repaired environment: {result.stderr}"
    assert re.search(r"^\\+ unset PACKET_CACHE$", result.stderr, re.MULTILINE), (
        "monitor.sh parsed packets but did not execute its cache cleanup under the repaired environment"
    )

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
