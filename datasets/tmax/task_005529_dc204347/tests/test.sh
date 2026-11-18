#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess

PIPELINE_DIR = "/home/user/pipeline_binaries"
CUSTOM_BINARY = os.path.join(PIPELINE_DIR, "custom_crypto_auth")
SUID_VIOLATORS_FILE = "/home/user/suid_violators.txt"
EXTRACTED_SBOX_FILE = "/home/user/extracted_sbox.bin"
MAX_DIFF_FILE = "/home/user/max_diff.txt"
RUST_PROJECT_DIR = "/home/user/ddt_analyzer"
CARGO_TOML = os.path.join(RUST_PROJECT_DIR, "Cargo.toml")
EXPECTED_SUID = sorted([
    os.path.join(PIPELINE_DIR, "custom_crypto_auth"),
    os.path.join(PIPELINE_DIR, "vuln_suid_bin"),
])


def extract_symbol(path, symbol_name):
    symbols = subprocess.run(
        ["readelf", "-Ws", "--wide", path],
        check=True, text=True, capture_output=True
    ).stdout

    symbol = None
    pattern = re.compile(
        r"^\s*\d+:\s+([0-9A-Fa-f]+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$"
    )
    for line in symbols.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        value, size, sym_type, bind, _visibility, section_index, name = match.groups()
        if name == symbol_name and sym_type == "OBJECT" and bind in ("GLOBAL", "WEAK") and section_index.isdigit():
            symbol = (int(value, 16), int(size), int(section_index))
            break

    assert symbol is not None, f"ELF symbol {symbol_name} was not found as a public object in {path}."
    value, size, section_index = symbol
    assert size == 256, f"{symbol_name} must be exactly 256 bytes, got {size}."

    sections = subprocess.run(
        ["readelf", "-SW", "--wide", path],
        check=True, text=True, capture_output=True
    ).stdout
    section_pattern = re.compile(
        r"^\s*\[\s*(\d+)\]\s+\S+\s+\S+\s+([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)"
    )
    target_section = None
    for line in sections.splitlines():
        match = section_pattern.match(line)
        if match and int(match.group(1)) == section_index:
            target_section = tuple(int(v, 16) for v in match.groups()[1:])
            break

    assert target_section is not None, f"Could not locate section {section_index} containing {symbol_name}."
    section_address, section_offset, section_size = target_section
    relative = value - section_address
    assert 0 <= relative and relative + size <= section_size, f"{symbol_name} lies outside its ELF section."

    with open(path, "rb") as binary:
        binary.seek(section_offset + relative)
        data = binary.read(size)
    assert len(data) == size
    return data


def differential_uniformity(sbox):
    assert len(sbox) == 256
    maximum = 0
    for input_difference in range(1, 256):
        counts = [0] * 256
        for x in range(256):
            counts[sbox[x] ^ sbox[x ^ input_difference]] += 1
        maximum = max(maximum, max(counts))
    return maximum


def run_analyzer():
    if os.path.exists(MAX_DIFF_FILE):
        os.remove(MAX_DIFF_FILE)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=RUST_PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Rust analyzer failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(MAX_DIFF_FILE), f"Analyzer did not create {MAX_DIFF_FILE}."
    with open(MAX_DIFF_FILE, "r") as output:
        content = output.read().strip()
    assert content.isdigit(), f"{MAX_DIFF_FILE} must contain a single integer value, got: '{content}'"
    return int(content)


def test_suid_violators_file():
    assert os.path.isfile(SUID_VIOLATORS_FILE), f"{SUID_VIOLATORS_FILE} does not exist."

    # Recompute the expected SUID violators from the actual directory state.
    expected_violators = []
    if os.path.isdir(PIPELINE_DIR):
        for root, _, files in os.walk(PIPELINE_DIR):
            for filename in files:
                path = os.path.join(root, filename)
                if os.path.isfile(path) and (os.stat(path).st_mode & stat.S_ISUID):
                    expected_violators.append(path)
    expected_violators.sort()

    with open(SUID_VIOLATORS_FILE, "r") as violations:
        actual_violators = [line.strip() for line in violations if line.strip()]

    assert actual_violators == expected_violators, (
        f"Contents of {SUID_VIOLATORS_FILE} do not match the expected sorted list of SUID binaries.\n"
        f"Expected: {expected_violators}\nActual: {actual_violators}"
    )
    # The audited inputs must not be mutated to make the dynamically computed list empty.
    assert expected_violators == EXPECTED_SUID, (
        f"Pipeline SUID state was modified. Expected {EXPECTED_SUID}, got {expected_violators}."
    )


def test_extracted_sbox_file():
    assert os.path.isfile(EXTRACTED_SBOX_FILE), f"{EXTRACTED_SBOX_FILE} does not exist."
    with open(EXTRACTED_SBOX_FILE, "rb") as extracted:
        data = extracted.read()

    assert len(data) == 256, f"{EXTRACTED_SBOX_FILE} must be exactly 256 bytes long, got {len(data)} bytes."

    # Preserve the original expected-content assertion.
    expected_data = bytes(range(256))
    assert data == expected_data, f"The contents of {EXTRACTED_SBOX_FILE} do not match the expected CUSTOM_SBOX data."

    # Also derive the answer from the ELF symbol itself.
    assert os.path.isfile(CUSTOM_BINARY), f"{CUSTOM_BINARY} does not exist."
    assert data == extract_symbol(CUSTOM_BINARY, "CUSTOM_SBOX"), (
        f"{EXTRACTED_SBOX_FILE} does not match the CUSTOM_SBOX symbol in the ELF binary."
    )


def test_rust_project_exists():
    assert os.path.isfile(CARGO_TOML), f"Rust project not found. Expected {CARGO_TOML} to exist."
    assert os.path.isfile(os.path.join(RUST_PROJECT_DIR, "src", "main.rs")), "Rust project has no src/main.rs."


def test_max_diff_file():
    assert os.path.isfile(MAX_DIFF_FILE), f"{MAX_DIFF_FILE} does not exist."
    with open(MAX_DIFF_FILE, "r") as output:
        content = output.read().strip()
    assert content.isdigit(), f"{MAX_DIFF_FILE} must contain a single integer value, got: '{content}'"
    assert int(content) == 256, f"Expected maximum differential uniformity to be 256, but got {content}."


def test_rust_analyzer_compiles_and_handles_derived_inputs():
    subprocess.run(
        ["cargo", "clean", "--manifest-path", CARGO_TOML],
        cwd=RUST_PROJECT_DIR,
        check=True,
        text=True,
        capture_output=True,
        timeout=60,
    )
    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=RUST_PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Rust project does not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"

    with open(EXTRACTED_SBOX_FILE, "rb") as extracted:
        original_sbox = extracted.read()

    rng = random.SystemRandom()
    permutation = list(range(256))
    rng.shuffle(permutation)
    challenges = [bytes(permutation), bytes(rng.randrange(256) for _ in range(256))]

    try:
        for challenge in challenges:
            with open(EXTRACTED_SBOX_FILE, "wb") as extracted:
                extracted.write(challenge)
            actual = run_analyzer()
            expected = differential_uniformity(challenge)
            assert actual == expected, (
                f"Analyzer returned {actual} for a verifier-generated S-box; expected {expected}."
            )
    finally:
        with open(EXTRACTED_SBOX_FILE, "wb") as extracted:
            extracted.write(original_sbox)

    actual = run_analyzer()
    expected = differential_uniformity(original_sbox)
    assert actual == expected, f"Analyzer returned {actual} for the extracted S-box; expected {expected}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
