#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import textwrap

PROJECT_DIR = "/home/user/packet_project"
REPORT_FILE = "/home/user/report.txt"
FUZZ_SCRIPT = os.path.join(PROJECT_DIR, "fuzz.sh")
PARSER_C = os.path.join(PROJECT_DIR, "parser.c")
SAMPLE_PCAP = os.path.join(PROJECT_DIR, "sample.pcap")

EXPECTED_MAKEFILE = "parser: parser.c\n\tgcc -g -o parser parser.c -lpcap\n\ntest: parser\n\t./test.sh\n"
EXPECTED_TEST_SH = "#!/bin/bash\n./parser sample.pcap\nif [ $? -eq 0 ]; then\n    echo \"Test passed\"\n    exit 0\nelse\n    echo \"Test failed\"\n    exit 1\nfi\n"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_protected_build_files_unchanged():
    with open(os.path.join(PROJECT_DIR, "Makefile"), "r") as f:
        assert f.read() == EXPECTED_MAKEFILE, "Makefile was modified."
    with open(os.path.join(PROJECT_DIR, "test.sh"), "r") as f:
        assert f.read() == EXPECTED_TEST_SH, "test.sh was modified."


def test_make_test_success():
    assert os.path.isdir(PROJECT_DIR), f"Project directory {PROJECT_DIR} is missing."
    result = run(["make", "clean"], cwd=PROJECT_DIR) if os.path.exists(os.path.join(PROJECT_DIR, "clean")) else None
    result = run(["make", "test"], cwd=PROJECT_DIR, timeout=30)
    assert result.returncode == 0, f"'make test' failed. stdout: {result.stdout}, stderr: {result.stderr}"


def test_report_content():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} is missing."
    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]
    assert len(lines) == 2, f"Expected exactly 2 lines in {REPORT_FILE}, found {len(lines)}."
    assert lines[0] == "7", f"Expected packet number '7' on line 1, found '{lines[0]}'."
    assert lines[1] == "process_payload", f"Expected function 'process_payload' on line 2, found '{lines[1]}'."


def test_sample_capture_shape():
    from scapy.all import rdpcap, Raw
    packets = rdpcap(SAMPLE_PCAP)
    assert len(packets) == 10, "sample.pcap no longer contains the original ten packets."
    lengths = [len(bytes(p[Raw].load)) if Raw in p else -1 for p in packets]
    assert lengths == [10, 10, 10, 10, 10, 10, 100, 10, 10, 10], "sample.pcap was modified."


def test_fuzz_script_exists_executable_and_is_bash():
    assert os.path.isfile(FUZZ_SCRIPT), f"Fuzzer script {FUZZ_SCRIPT} is missing."
    assert os.access(FUZZ_SCRIPT, os.X_OK), f"Fuzzer script {FUZZ_SCRIPT} is not executable."
    with open(FUZZ_SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r"^#!\s*(/usr/bin/env\s+)?(/bin/)?bash(?:\s|$)", first_line), "fuzz.sh must be a Bash script."
    syntax = run(["bash", "-n", FUZZ_SCRIPT])
    assert syntax.returncode == 0, f"fuzz.sh has invalid Bash syntax: {syntax.stderr}"


def test_fuzzer_really_isolates_and_finds_a_dynamic_crash(tmp_path):
    from scapy.all import Ether, IP, TCP, Raw, wrpcap

    target = secrets.choice([3, 4, 5, 6, 8, 9])
    nonce = secrets.token_hex(12)
    packets = []
    for i in range(1, 11):
        marker = f"VERIFY_{nonce}_{i}".encode()
        packets.append(Ether()/IP(src="10.23.0.2", dst="10.23.0.1")/TCP(sport=2000+i, dport=80)/Raw(load=marker))

    synthetic = tmp_path / "sample.pcap"
    wrpcap(str(synthetic), packets)
    log_file = tmp_path / "calls.jsonl"
    shim = tmp_path / "parser"
    shim.write_text(textwrap.dedent(f'''\
        #!/usr/bin/python3
        import json, os, sys
        from scapy.all import rdpcap, Raw
        path = sys.argv[1] if len(sys.argv) > 1 else ""
        try:
            packets = rdpcap(path)
        except Exception:
            packets = []
        ids = []
        prefix = {('VERIFY_' + nonce + '_')!r}.encode()
        for packet in packets:
            data = bytes(packet[Raw].load) if Raw in packet else b""
            if data.startswith(prefix):
                try:
                    ids.append(int(data[len(prefix):].decode()))
                except Exception:
                    pass
        with open(os.environ["FUZZ_VERIFY_LOG"], "a") as out:
            out.write(json.dumps({{"count": len(packets), "ids": ids}}) + "\\n")
        if {target} in ids:
            os._exit(139)
        os._exit(0)
    '''))
    shim.chmod(0o755)

    sandbox = tmp_path / "project"
    sandbox.mkdir()
    shutil.copy2(FUZZ_SCRIPT, sandbox / "fuzz.sh")
    shutil.copy2(synthetic, sandbox / "sample.pcap")
    shutil.copy2(shim, sandbox / "parser")

    env = os.environ.copy()
    env["FUZZ_VERIFY_LOG"] = str(log_file)
    result = run(["bash", "./fuzz.sh"], cwd=str(sandbox), env=env, timeout=45)

    assert log_file.exists(), "fuzz.sh never executed ./parser."
    records = [json.loads(line) for line in log_file.read_text().splitlines() if line.strip()]
    assert records, "fuzz.sh never fed a capture to ./parser."
    assert all(r["count"] == 1 for r in records), "fuzz.sh must feed isolated one-packet captures to ./parser."
    seen = {r["ids"][0] for r in records if len(r["ids"]) == 1}
    assert set(range(1, target + 1)).issubset(seen), "fuzz.sh did not test packets individually up to the crashing packet."

    combined = result.stdout + "\n" + result.stderr
    crash_lines = [line for line in combined.splitlines() if re.search(r"crash|segmentation|segfault|fail|caus", line, re.I)]
    reported = set()
    for line in crash_lines:
        reported.update(int(n) for n in re.findall(r"(?<!\d)(10|[1-9])(?!\d)", line))
    assert target in reported, f"fuzz.sh did not report dynamically selected crashing packet {target}. Output: {combined}"
    assert not (reported - {target}), f"fuzz.sh reported non-crashing packet numbers as crashes: {sorted(reported - {target})}"


def test_parser_c_retains_and_invokes_core_logic():
    assert os.path.isfile(PARSER_C), f"Source file {PARSER_C} is missing."
    content = open(PARSER_C, "r").read()
    assert "process_payload" in content, "Core logic function 'process_payload' was removed from parser.c."
    assert re.search(r"pcap_open_offline\s*\(", content), "parser no longer opens a pcap capture."
    assert re.search(r"pcap_loop\s*\(", content), "parser no longer processes capture packets."
    assert re.search(r"process_payload\s*\(\s*packet\s*\+", content), "packet_handler no longer passes packet payloads to process_payload."
    match = re.search(r"void\s+process_payload\s*\([^)]*\)\s*\{(?P<body>.*?)\n\}", content, re.S)
    assert match, "Could not find the process_payload function definition."
    body = match.group("body")
    assert "payload" in body and "len" in body, "process_payload no longer processes its payload and length."
    assert re.search(r"\b(memcpy|memmove)\s*\(", body), "The payload-copying core logic was removed rather than made safe."


def test_parser_is_safe_on_derived_oversized_inputs(tmp_path):
    from scapy.all import Ether, IP, TCP, Raw, wrpcap

    binary = tmp_path / "parser_sanitized"
    build = run([
        "gcc", "-g", "-O1", "-fno-omit-frame-pointer",
        "-fsanitize=address,undefined", "-o", str(binary), PARSER_C, "-lpcap"
    ], cwd=PROJECT_DIR, timeout=30)
    assert build.returncode == 0, f"parser.c does not compile with sanitizers: {build.stderr}"

    sizes = [51, 73 + secrets.randbelow(31), 160 + secrets.randbelow(120), 700 + secrets.randbelow(200)]
    for index, size in enumerate(sizes):
        payload = secrets.token_bytes(size)
        capture = tmp_path / f"oversized_{index}.pcap"
        packet = Ether()/IP(src="172.20.1.2", dst="172.20.1.1")/TCP(sport=4321, dport=80)/Raw(load=payload)
        wrpcap(str(capture), [packet])
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:abort_on_error=1"
        result = run([str(binary), str(capture)], env=env, timeout=15)
        assert result.returncode == 0, (
            f"Sanitizers detected unsafe payload handling for a derived {size}-byte payload. "
            f"stdout: {result.stdout}, stderr: {result.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
