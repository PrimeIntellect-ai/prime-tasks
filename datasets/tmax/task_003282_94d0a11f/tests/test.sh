#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import json
import os
import pathlib
import random
import re
import resource
import shutil
import subprocess
import tempfile
import uuid

import pytest

FILTER_BIN = "/home/user/qemu_net_filter"
SOURCE_DIR = "/home/user/filter_src"
LOG_FILE = "/home/user/filter.log"
LOGROTATE_CONF = "/home/user/logrotate.conf"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
ORACLE = "/app/deploy-validator"


def no_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run_program(program, path):
    return subprocess.run(
        [program, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        preexec_fn=no_core_dumps,
    )


def oracle_accepts(path):
    return run_program(ORACLE, path).returncode == 0


def build_submitted_rust():
    source_root = pathlib.Path(SOURCE_DIR)
    assert source_root.is_dir(), f"Rust source directory missing at {SOURCE_DIR}"
    rust_files = sorted(source_root.rglob("*.rs"))
    assert rust_files, f"No Rust source files found under {SOURCE_DIR}"
    assert all(p.is_file() and p.stat().st_size > 0 for p in rust_files), "Rust source files must be non-empty regular files"

    build_root = tempfile.mkdtemp(prefix="qemu_filter_build_")
    manifest = source_root / "Cargo.toml"
    if manifest.is_file():
        metadata = subprocess.run(
            ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", str(manifest)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert metadata.returncode == 0, f"Invalid Cargo project: {metadata.stderr}"
        data = json.loads(metadata.stdout)
        bin_names = []
        for package in data.get("packages", []):
            for target in package.get("targets", []):
                if "bin" in target.get("kind", []):
                    bin_names.append(target["name"])
        assert bin_names, "Cargo project defines no Rust binary target"

        result = subprocess.run(
            ["cargo", "build", "--release", "--manifest-path", str(manifest), "--target-dir", build_root],
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"Rust source failed to compile: {result.stderr}"
        candidates = [os.path.join(build_root, "release", name) for name in bin_names]
        candidates = [p for p in candidates if os.path.isfile(p) and os.access(p, os.X_OK)]
        preferred = [p for p in candidates if os.path.basename(p) in {"qemu_net_filter", "qemu-net-filter"}]
        if preferred:
            candidates = preferred
        assert len(candidates) == 1, f"Could not identify one compiled filter binary; candidates: {candidates}"
        return candidates[0]

    preferred = [source_root / "main.rs", source_root / "src" / "main.rs"]
    mains = [p for p in preferred if p.is_file()]
    if not mains and len(rust_files) == 1:
        mains = rust_files
    assert len(mains) == 1, "Provide either a Cargo binary project or one identifiable main.rs"
    output = os.path.join(build_root, "qemu_net_filter")
    result = subprocess.run(
        ["rustc", "--edition=2021", "-O", str(mains[0]), "-o", output],
        cwd=SOURCE_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust source failed to compile: {result.stderr}"
    return output


@pytest.fixture(scope="session")
def rebuilt_filter():
    return build_submitted_rust()


def test_filter_executable_exists(rebuilt_filter):
    assert os.path.exists(FILTER_BIN), f"Filter binary missing at {FILTER_BIN}"
    assert os.path.isfile(FILTER_BIN), f"{FILTER_BIN} is not a file"
    assert os.access(FILTER_BIN, os.X_OK), f"{FILTER_BIN} is not executable"
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Installed filter must be a compiled executable, not a script"
    with open(rebuilt_filter, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Submitted Rust source did not produce an ELF executable"
    with open(FILTER_BIN, "rb") as f:
        installed_hash = hashlib.sha256(f.read()).digest()
    with open(ORACLE, "rb") as f:
        oracle_hash = hashlib.sha256(f.read()).digest()
    assert installed_hash != oracle_hash, "Filter must not be a copy of the proprietary validator"


def make_cases():
    case_dir = tempfile.mkdtemp(prefix="qnf_" + uuid.uuid4().hex + "_")
    cases = []

    # Preserve the original clean/evil corpus assertions, but copy every input to
    # neutral, randomized paths so the directory name cannot reveal its class.
    originals = []
    originals.extend((os.path.join(CLEAN_DIR, f), True) for f in os.listdir(CLEAN_DIR)
                     if os.path.isfile(os.path.join(CLEAN_DIR, f)))
    originals.extend((os.path.join(EVIL_DIR, f), False) for f in os.listdir(EVIL_DIR)
                     if os.path.isfile(os.path.join(EVIL_DIR, f)))
    random.SystemRandom().shuffle(originals)
    for source, expected in originals:
        destination = os.path.join(case_dir, uuid.uuid4().hex + ".cfg")
        shutil.copyfile(source, destination)
        assert oracle_accepts(destination) == expected
        cases.append((destination, expected))

    rng = random.SystemRandom()
    generated = []
    for _ in range(24):
        octets = [rng.randrange(256) for _ in range(6)]
        mac = ":".join(f"{x:02x}" for x in octets)
        cidr = rng.randrange(16, 33)
        generated.append(f"-machine q35 -netdev user,id=n{rng.randrange(10000)},net=10.{rng.randrange(256)}.{rng.randrange(256)}.0/{cidr} -device virtio-net-pci,mac={mac}\n")
    for _ in range(18):
        fields = rng.randrange(1, 6)
        mac = ":".join(f"{rng.randrange(256):02x}" for _ in range(fields))
        generated.append(f"-netdev user,id=x{rng.randrange(10000)},net=10.20.0.0/24 -device e1000,mac={mac}\n")
    for _ in range(18):
        cidr = rng.randrange(0, 16)
        mac = ":".join(f"{rng.randrange(256):02x}" for _ in range(6))
        generated.append(f"-name vm{rng.randrange(10000)} -netdev user,id=y,net=10.{rng.randrange(256)}.0.0/{cidr} -device e1000,mac={mac}\n")
    generated.extend([
        "-machine q35 -m 1024\n",
        "-netdev user,id=n0,net=192.168.1.0/8 -device e1000,mac=52:54:00:12:34:56\n",
        "prefix mac=52:54:00:12:34 suffix\n",
        "prefix net=10.1.2.0/15 suffix\n",
    ])
    rng.shuffle(generated)
    for content in generated:
        destination = os.path.join(case_dir, uuid.uuid4().hex + ".cfg")
        with open(destination, "w") as f:
            f.write(content)
        cases.append((destination, oracle_accepts(destination)))

    assert any(expected for _, expected in cases)
    assert any(not expected for _, expected in cases)
    rng.shuffle(cases)
    return cases


def verify_behavior_and_logging(program, cases):
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    started = datetime.datetime.now() - datetime.timedelta(seconds=2)
    failures = []
    expected_logs = []
    for path, expected_accept in cases:
        result = run_program(program, path)
        actual_accept = result.returncode == 0
        if actual_accept != expected_accept:
            failures.append(os.path.basename(path))
        expected_logs.append((os.path.basename(path), "ACCEPTED" if expected_accept else "REJECTED"))
    ended = datetime.datetime.now() + datetime.timedelta(seconds=2)

    assert not failures, f"Incorrect classifications for {len(failures)} inputs: {', '.join(failures[:5])}"
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} was not created"
    with open(LOG_FILE, "r") as f:
        log_lines = f.read().splitlines()
    assert len(log_lines) == len(expected_logs), f"Expected exactly {len(expected_logs)} log lines, found {len(log_lines)}"

    pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (.*) - (ACCEPTED|REJECTED)$")
    for index, (line, (expected_name, expected_status)) in enumerate(zip(log_lines, expected_logs)):
        match = pattern.fullmatch(line)
        assert match, f"Invalid log line {index + 1}: {line!r}"
        timestamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
        assert started <= timestamp <= ended, f"Log line {index + 1} has a stale or fabricated timestamp"
        assert match.group(2) == expected_name, f"Log line {index + 1} names the wrong file"
        assert match.group(3) == expected_status, f"Log line {index + 1} has the wrong status"


def test_filter_behavior_and_logging(rebuilt_filter):
    cases = make_cases()
    verify_behavior_and_logging(FILTER_BIN, cases)
    # Compile and execute the submitted Rust source independently, ensuring the
    # working implementation is actually present in filter_src.
    verify_behavior_and_logging(rebuilt_filter, cases)


def test_logrotate_config():
    assert os.path.exists(LOGROTATE_CONF), f"Logrotate config missing at {LOGROTATE_CONF}"
    res = subprocess.run(["logrotate", "-d", LOGROTATE_CONF], capture_output=True, text=True)
    assert res.returncode == 0, f"logrotate config syntax error: {res.stderr}"
    with open(LOGROTATE_CONF, "r") as f:
        content = f.read()
    content_no_comments = re.sub(r"#.*", "", content)
    assert re.search(r"\bdaily\b", content_no_comments), "Logrotate config missing 'daily' directive"
    assert re.search(r"\brotate\s+5\b", content_no_comments), "Logrotate config missing 'rotate 5' directive"
    assert re.search(r"\bcompress\b", content_no_comments), "Logrotate config missing 'compress' directive"
    assert re.search(r"\bcreate\s+0?644\b", content_no_comments), "Logrotate config missing 'create 0644' directive"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
