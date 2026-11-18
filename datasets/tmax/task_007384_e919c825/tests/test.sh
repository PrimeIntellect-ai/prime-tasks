#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/snapshot_configs.sh"
OUTPUT_PATH = "/home/user/config_snapshot.log"
BASELINE_PATH = "/home/user/system/baseline.stamp"
OVERRIDES_PATH = "/home/user/system/overrides.txt"
CONFIGS_DIR = "/home/user/system/configs"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable by the owner"


def test_snapshot_output_correct():
    assert os.path.exists(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}. Did you run the script?"

    assert os.path.exists(BASELINE_PATH), "Baseline stamp file missing"
    assert os.path.exists(OVERRIDES_PATH), "Overrides file missing"

    baseline_mtime = os.path.getmtime(BASELINE_PATH)

    with open(OVERRIDES_PATH, 'r') as f:
        overrides = set(line.strip() for line in f if line.strip())

    results = []
    for root, _, files in os.walk(CONFIGS_DIR):
        for file in files:
            if file.endswith('.conf'):
                filepath = os.path.join(root, file)
                if filepath in overrides:
                    continue
                if os.path.getsize(filepath) == 0:
                    continue
                if os.path.getmtime(filepath) <= baseline_mtime:
                    continue

                with open(filepath, 'rb') as f:
                    content = f.read()

                chunk_index = 0
                for i in range(0, len(content), 50):
                    chunk = content[i:i+50]
                    h = hashlib.sha256(chunk).hexdigest()
                    results.append(f"{filepath}:{chunk_index}:{h}")
                    chunk_index += 1

    def sort_key(line):
        parts = line.split(':')
        return (parts[0], int(parts[1]))

    results.sort(key=sort_key)
    expected_content = "\n".join(results)

    with open(OUTPUT_PATH, 'r') as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"Content of {OUTPUT_PATH} does not match expected output.\n"
        f"Expected:\n{expected_content.strip()}\n\n"
        f"Actual:\n{actual_content.strip()}"
    )


def test_script_implementation_and_fresh_execution():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script_text = f.read()

    first_line = script_text.splitlines()[0] if script_text.splitlines() else ""
    assert re.match(r"^#!\s*(?:/usr/bin/env\s+bash|/bin/bash|/usr/bin/bash)(?:\s|$)", first_line), \
        "snapshot_configs.sh must be a Bash script"
    assert re.search(r"\bmktemp\b", script_text), "Script must securely create a temporary file with mktemp"
    assert re.search(r"\bmv\b", script_text), "Script must atomically rename the temporary output with mv"
    assert OUTPUT_PATH in script_text, "Script does not reference the required output path"
    assert not re.search(r"\b(?:python(?:2|3)?|perl|node(?:js)?|ruby|php)\b", script_text, re.IGNORECASE), \
        "Script references a forbidden scripting-language runtime"

    token = secrets.token_hex(8)
    test_dir = os.path.join(CONFIGS_DIR, "verify_" + token)
    os.makedirs(test_dir)

    included_a = os.path.join(test_dir, "alpha_" + token + ".conf")
    included_b = os.path.join(test_dir, "zeta_" + token + ".conf")
    excluded = os.path.join(test_dir, "excluded_" + token + ".conf")
    old_file = os.path.join(test_dir, "old_" + token + ".conf")
    empty_file = os.path.join(test_dir, "empty_" + token + ".conf")
    nonconf = os.path.join(test_dir, "other_" + token + ".txt")
    symlink_conf = os.path.join(test_dir, "link_" + token + ".conf")

    payload_a = secrets.token_bytes(575)
    payload_b = secrets.token_bytes(73)
    payload_excluded = secrets.token_bytes(111)

    for path, data in ((included_a, payload_a), (included_b, payload_b),
                       (excluded, payload_excluded), (old_file, secrets.token_bytes(90)),
                       (nonconf, secrets.token_bytes(80))):
        with open(path, "wb") as f:
            f.write(data)
    open(empty_file, "wb").close()
    os.symlink(included_a, symlink_conf)

    now_ns = os.stat(test_dir).st_mtime_ns
    baseline_ns = now_ns - 10_000_000_000
    os.utime(BASELINE_PATH, ns=(baseline_ns, baseline_ns))
    newer_ns = baseline_ns + 5_000_000_000
    older_ns = baseline_ns - 5_000_000_000
    for path in (included_a, included_b, excluded, empty_file, nonconf):
        os.utime(path, ns=(newer_ns, newer_ns))
    os.utime(old_file, ns=(older_ns, older_ns))

    with open(OVERRIDES_PATH, "w") as f:
        f.write("\n" + excluded + "\n\n/home/user/system/configs/missing_" + token + ".conf\n")

    expected = []
    for path, data in ((included_a, payload_a), (included_b, payload_b)):
        for index, offset in enumerate(range(0, len(data), 50)):
            digest = hashlib.sha256(data[offset:offset + 50]).hexdigest()
            expected.append(f"{path}:{index}:{digest}")
    expected.sort(key=lambda line: (line.rsplit(":", 2)[0], int(line.rsplit(":", 2)[1])))
    expected_content = "\n".join(expected)

    if os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    sentinel = "/tmp/snapshot_sentinel_" + token
    sentinel_data = b"atomic-write-sentinel-" + token.encode()
    with open(sentinel, "wb") as f:
        f.write(sentinel_data)
    os.chmod(sentinel, 0o444)
    os.symlink(sentinel, OUTPUT_PATH)

    completed = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Script failed when executed on fresh inputs (exit {completed.returncode}).\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    assert os.path.isfile(OUTPUT_PATH), "Script did not create the required snapshot output"
    assert not os.path.islink(OUTPUT_PATH), "Final output symlink was not atomically replaced"
    with open(sentinel, "rb") as f:
        assert f.read() == sentinel_data, "Script wrote through the destination instead of atomically replacing it"
    with open(OUTPUT_PATH, "r") as f:
        actual_content = f.read()
    assert actual_content.strip() == expected_content.strip(), (
        "Freshly executed script produced incorrect output for verifier-generated inputs.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
