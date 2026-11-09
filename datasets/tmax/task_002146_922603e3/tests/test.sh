#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import ipaddress
import json
import os
import random
import re
import secrets
import subprocess

PROJECT = "/home/user/net_classifier"
DEBUG_BIN = PROJECT + "/target/debug/net_classifier"
RELEASE_BIN = PROJECT + "/target/release/net_classifier"
SCRIPT = "/home/user/run_pipeline.sh"


def expected_output(line):
    entry = json.loads(line)
    try:
        blacklisted = ipaddress.ip_address(entry["source_ip"]) in ipaddress.ip_network("198.51.100.0/24")
    except ValueError:
        blacklisted = False
    exfiltration = entry["protocol"] == "DNS" and re.search(r"[0-9A-Fa-f]{33,}", entry["payload"]) is not None
    return ("DROP: " if blacklisted or exfiltration else "ACCEPT: ") + line


def run_classifier(bin_path, lines):
    proc = subprocess.run(
        [bin_path],
        input="\n".join(lines) + "\n",
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"classifier exited {proc.returncode}: {proc.stderr}"
    expected = "\n".join(expected_output(line) for line in lines) + "\n"
    assert proc.stdout == expected, f"unexpected classifier output\nexpected: {expected!r}\nactual: {proc.stdout!r}"


def test_vendor_package_fixed():
    lib_rs = "/app/vendor/packet_decode/src/lib.rs"
    assert os.path.exists(lib_rs), f"Missing {lib_rs}"
    with open(lib_rs, "r") as f:
        content = f.read()
        assert "Reuslt" not in content, "The deliberate typo 'Reuslt' was not fixed in lib.rs"
        assert "Result" in content, "The return type 'Result' is not present in lib.rs"

    proc = subprocess.run(["cargo", "check", "--quiet"], cwd="/app/vendor/packet_decode", text=True, capture_output=True, timeout=120)
    assert proc.returncode == 0, f"packet_decode still does not compile: {proc.stderr}"


def test_run_pipeline_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Missing integration script at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"The script {SCRIPT} is not executable"


def test_net_classifier_binary_exists_and_builds():
    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.exists(cargo_toml), "net_classifier Rust project is missing"
    proc = subprocess.run(["cargo", "build", "--release"], cwd=PROJECT, text=True, capture_output=True, timeout=180)
    assert proc.returncode == 0, f"net_classifier failed to build: {proc.stderr}"
    assert os.path.exists(DEBUG_BIN) or os.path.exists(RELEASE_BIN), "net_classifier binary not found"
    assert os.path.exists(RELEASE_BIN), "release net_classifier binary not found after cargo build --release"


def test_existing_adversarial_corpus_verification():
    assert os.path.exists(RELEASE_BIN), "net_classifier binary not found"
    evil_files = glob.glob("/app/corpora/evil/*")
    clean_files = glob.glob("/app/corpora/clean/*")
    assert len(evil_files) > 0, "No evil corpus files found"
    assert len(clean_files) > 0, "No clean corpus files found"

    evil_bypassed = []
    clean_modified = []
    for path in evil_files:
        for line in open(path).read().splitlines():
            if not line.strip():
                continue
            proc = subprocess.run([RELEASE_BIN], input=line, text=True, capture_output=True, timeout=10)
            if proc.returncode != 0 or proc.stdout != "DROP: " + line + "\n":
                evil_bypassed.append((os.path.basename(path), line, proc.stdout))

    for path in clean_files:
        for line in open(path).read().splitlines():
            if not line.strip():
                continue
            proc = subprocess.run([RELEASE_BIN], input=line, text=True, capture_output=True, timeout=10)
            if proc.returncode != 0 or proc.stdout != "ACCEPT: " + line + "\n":
                clean_modified.append((os.path.basename(path), line, proc.stdout))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} evil bypassed. Offending files: {', '.join(set(x[0] for x in evil_bypassed))}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} clean modified. Offending files: {', '.join(set(x[0] for x in clean_modified))}")
    assert not evil_bypassed and not clean_modified, " | ".join(errors)


def test_runtime_generated_classifier_cases():
    cases = []
    for i in range(12):
        long_hex = secrets.token_hex(random.randint(17, 35))
        exact_hex = secrets.token_hex(16)
        left = secrets.token_hex(random.randint(8, 16))
        right = secrets.token_hex(random.randint(8, 16))
        ordinary_ip = f"10.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"
        blacklisted_ip = f"198.51.100.{random.randint(0, 255)}"
        near_ip = random.choice([
            f"198.51.99.{random.randint(0, 255)}",
            f"198.51.101.{random.randint(0, 255)}",
            f"203.0.113.{random.randint(0, 255)}",
        ])
        entries = [
            {"protocol": "DNS", "source_ip": ordinary_ip, "payload": "q=" + long_hex + ".example"},
            {"protocol": "HTTP", "source_ip": ordinary_ip, "payload": long_hex},
            {"protocol": "DNS", "source_ip": ordinary_ip, "payload": "prefix-" + exact_hex + "-suffix"},
            {"protocol": "DNS", "source_ip": ordinary_ip, "payload": left + "." + right},
            {"protocol": random.choice(["HTTP", "TCP", "dns"]), "source_ip": blacklisted_ip, "payload": "normal payload " + secrets.token_hex(5)},
            {"protocol": "DNS", "source_ip": near_ip, "payload": "query-" + secrets.token_hex(8) + ".test"},
        ]
        for entry in entries:
            if (i + len(cases)) % 2:
                cases.append(json.dumps(entry, separators=(",", ":")))
            else:
                cases.append(json.dumps(entry))

    random.SystemRandom().shuffle(cases)
    run_classifier(RELEASE_BIN, cases)


def test_run_pipeline_functionality(tmp_path):
    assert os.path.exists(SCRIPT), "Missing script"
    long_hex = secrets.token_hex(20)
    raw_lines = [
        '{"protocol": "HTTP", "source_ip": "192.168.1.5", "payload": "GET / HTTP/1.1"}',
        json.dumps({"protocol": "DNS", "source_ip": "10.20.30.40", "payload": "query-" + long_hex + ".invalid"}, separators=(",", ":")),
        json.dumps({"protocol": "UDP", "source_ip": f"198.51.100.{random.randint(0, 255)}", "payload": "ordinary"}),
        json.dumps({"protocol": "DNS", "source_ip": "203.0.113.9", "payload": secrets.token_hex(16)}),
    ]
    prefixes = [
        "2023-10-10 12:00:00 [INFO] PID:1234 ",
        f"{secrets.token_hex(6)} daemon[{random.randint(100, 9999)}]: ",
        "", 
        "Sep 11 host net-agent: ",
    ]
    test_log = tmp_path / "network logs.txt"
    test_log.write_text("\n".join(prefix + line for prefix, line in zip(prefixes, raw_lines)) + "\n")

    proc = subprocess.run([SCRIPT, str(test_log)], capture_output=True, text=True, timeout=20)
    assert proc.returncode == 0, f"pipeline exited {proc.returncode}: {proc.stderr}"
    expected = "\n".join(expected_output(line) for line in raw_lines) + "\n"
    assert proc.stdout == expected, f"pipeline did not strip prefixes or preserve exact classifier output: {proc.stdout!r}"

    missing = tmp_path / "does-not-exist.log"
    proc = subprocess.run([SCRIPT, str(missing)], capture_output=True, text=True, timeout=20)
    assert proc.returncode != 0, "pipeline must fail gracefully for a nonexistent input file"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
