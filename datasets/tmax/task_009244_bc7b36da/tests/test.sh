#!/bin/bash
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

run_verification() {
    local token expected_pcap trace_log

    mkdir -p /home/user/data || return 1
    find /home/user/data -maxdepth 1 -type f -name '*.pcap' -delete || return 1

    token=$(python3 -c 'import secrets; print(secrets.token_hex(8))') || return 1
    expected_pcap="/home/user/data/audit capture ${token}.pcap"
    trace_log=$(mktemp /tmp/analyzer-strace.XXXXXX) || return 1

    cat > /tmp/audit-packet.hex <<'EOF'
000000 00 00 00 00 00 00 00 00 00 00 00 00 08 00 45 00
EOF
    text2pcap /tmp/audit-packet.hex "$expected_pcap" >/tmp/text2pcap-audit.log 2>&1 || return 1

    rm -f /home/user/success.log || return 1
    cd /home/user/analyzer || return 1
    cargo clean >/tmp/cargo-clean-audit.log 2>&1 || return 1
    env -u PCAP_FILTER strace -f -s 10000 -e trace=execve -o "$trace_log" \
        timeout 120 cargo run --quiet >/tmp/cargo-run-audit.log 2>&1 || {
            cat /tmp/cargo-run-audit.log
            return 1
        }

    export EXPECTED_PCAP="$expected_pcap"
    export TSHARK_TRACE_LOG="$trace_log"

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
from pathlib import Path


def test_success_log_exists_and_correct():
    success_log = Path("/home/user/success.log")
    assert success_log.is_file(), "The file /home/user/success.log does not exist. Did the program run successfully?"

    content = success_log.read_text().strip()
    assert "Processing complete." in content, f"Expected 'Processing complete.' in success.log, but found: {content}"


def test_env_file_fixed():
    env_file = Path("/home/user/analyzer/.env")
    assert env_file.is_file(), "/home/user/analyzer/.env does not exist."

    content = env_file.read_text()
    assert "tcp.port == 80" in content, "The PCAP_FILTER in .env is not correctly set to 'tcp.port == 80'."

    assignments = []
    for line in content.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.match(r"^\s*(?:export\s+)?PCAP_FILTER\s*=\s*(.*?)\s*$", line)
        if match:
            value = match.group(1).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            assignments.append(value)

    assert assignments == ["tcp.port == 80"], (
        "The active PCAP_FILTER assignment in .env must be exactly 'tcp.port == 80'."
    )


def test_main_rs_fixed():
    main_rs = Path("/home/user/analyzer/src/main.rs")
    assert main_rs.is_file(), "/home/user/analyzer/src/main.rs does not exist."

    content = main_rs.read_text()

    # The original buggy line: let cmd = format!("tshark -r {} -Y '{}' -w /tmp/filtered.pcap", filename, filter);
    # Check that the exact unquoted format string is no longer present.
    buggy_pattern = 'tshark -r {} -Y'
    assert buggy_pattern not in content, "The Rust code still contains the unquoted filename bug ('tshark -r {} -Y')."


def test_program_executed_tshark_with_separate_correct_arguments():
    expected_pcap = os.environ["EXPECTED_PCAP"]
    trace = Path(os.environ["TSHARK_TRACE_LOG"])
    assert trace.is_file(), "The cargo run execution trace was not produced."

    quoted = r'"(?:\\.|[^"\\])*"'
    invocations = []
    for line in trace.read_text(errors="replace").splitlines():
        if not line.rstrip().endswith("= 0"):
            continue
        match = re.search(r'execve\((' + quoted + r'), \[(.*?)\],', line)
        if not match:
            continue
        try:
            executable = ast.literal_eval(match.group(1))
            args = [ast.literal_eval(token) for token in re.findall(quoted, match.group(2))]
        except (SyntaxError, ValueError):
            continue
        if Path(executable).name == "tshark":
            invocations.append(args)

    assert invocations, "cargo run completed without executing tshark."

    def has_option(args, option, value):
        return any(args[i] == option and args[i + 1] == value for i in range(len(args) - 1))

    matching = [
        args for args in invocations
        if has_option(args, "-r", expected_pcap)
        and has_option(args, "-Y", "tcp.port == 80")
    ]
    assert matching, (
        "tshark was not executed with the generated space-containing pcap path as one -r argument "
        "and 'tcp.port == 80' as one -Y argument. Observed invocations: " + repr(invocations)
    )
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_verification; then
    reward=1
fi
exit 0
