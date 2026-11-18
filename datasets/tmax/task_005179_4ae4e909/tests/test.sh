#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import collections
import os
import re
import shutil
import subprocess
import tempfile

SCRIPT = "/home/user/analyze.sh"
RAW_DIR = "/home/user/raw_configs"
SUMMARY = "/home/user/profile_summary.txt"
ORIGINAL_EXPECTED = [
    "25 web,frontend,us-east",
    "15 db,backend,us-west",
    "5 cache,backend,none",
    "5 cache,backend,us-east",
]


def read_summary():
    assert os.path.isfile(SUMMARY), f"Output file {SUMMARY} does not exist."
    with open(SUMMARY, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def assert_summary(expected):
    actual = read_summary()
    assert actual == expected, (
        f"Contents of {SUMMARY} do not match expected output.\n"
        f"Expected:\n{chr(10).join(expected)}\n"
        f"Got:\n{chr(10).join(actual)}"
    )


def run_script():
    if os.path.exists(SUMMARY):
        os.unlink(SUMMARY)
    result = subprocess.run(
        ["/bin/bash", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode}.\nOutput:\n{result.stdout}"
    )
    assert os.path.isfile(SUMMARY), f"Running {SCRIPT} did not create {SUMMARY}."


def assert_parallel_construct():
    with open(SCRIPT, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    source = source.replace("\\\n", " ")
    active = "\n".join(
        line for line in source.splitlines()
        if not re.match(r"^\s*#", line)
    )
    uses_xargs_p = bool(re.search(
        r"\bxargs\b[^\n]*(?:\s-P(?:\s|=|\d)|--max-procs(?:\s|=))", active
    ))
    uses_parallel = bool(re.search(r"(?:^|[\s;/|&])parallel(?:\s|$)", active))
    uses_background_jobs = bool(
        re.search(r"(?<![>&])&(?![>&])", active) and
        re.search(r"\bwait(?:\s|$)", active)
    )
    assert uses_xargs_p or uses_parallel or uses_background_jobs, (
        "analyze.sh does not use a required parallel-processing construct "
        "(xargs -P, GNU parallel, or background jobs with wait)."
    )


def reference_summary(directory):
    counts = collections.Counter()
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        values = {}
        with open(path, "r", encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.rstrip("\r\n")
                if not line.strip() or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                values[key.strip().lower()] = value.strip().lower()
        profile = ",".join(values.get(key, "none") for key in ("role", "tier", "region"))
        counts[profile] += 1
    return [
        f"{count} {profile}"
        for profile, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    ]


def create_fuzzed_fleet(directory):
    os.makedirs(directory)
    roles = ["API", "Worker", "DB", "Cache", "Proxy"]
    tiers = ["FrontEnd", "BACKEND", "Batch", "Edge"]
    regions = ["US-East", "eu-WEST", "AP-South"]

    for i in range(50):
        path = os.path.join(directory, f"node_{i:03d}.conf")
        with open(path, "w", encoding="utf-8") as f:
            f.write("# dynamically generated configuration\n\n")
            if i % 11 != 0:
                f.write(f"  RoLe = {roles[(i * 3) % len(roles)]}  \n")
            if i % 7 != 0:
                f.write(f"TIER=  {tiers[(i * 5) % len(tiers)]}\n")
            if i % 9 != 0:
                f.write(f" region = {regions[(i * 2) % len(regions)]}  \n")
            f.write("# ignored=value\n")
            f.write(f" timeout = {10 + i} \n")
            f.write("note = value=with=equals\n")


# Preserve the original verifier's assertions.
assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
assert_summary(ORIGINAL_EXPECTED)
assert_parallel_construct()

# Ensure the submitted artifact itself produces the original required result.
run_script()
assert_summary(ORIGINAL_EXPECTED)

# Replace the fleet temporarily and derive the expected answer independently.
backup_root = tempfile.mkdtemp(prefix="raw_configs_backup_")
backup_raw = os.path.join(backup_root, "raw_configs")
shutil.move(RAW_DIR, backup_raw)
try:
    create_fuzzed_fleet(RAW_DIR)
    expected = reference_summary(RAW_DIR)
    run_script()
    assert_summary(expected)
finally:
    if os.path.exists(RAW_DIR):
        shutil.rmtree(RAW_DIR)
    shutil.move(backup_raw, RAW_DIR)
    shutil.rmtree(backup_root)

# Leave the requested output corresponding to the original fleet.
run_script()
assert_summary(ORIGINAL_EXPECTED)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
