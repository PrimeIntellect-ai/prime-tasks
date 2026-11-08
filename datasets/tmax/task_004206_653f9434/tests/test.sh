#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/validate_manifest.py"
DB = "http://example.org/db/"


def run_validator(path, expected):
    res = subprocess.run(
        ["python3", SCRIPT_PATH, str(path)],
        capture_output=True,
        text=True,
        timeout=10,
        cwd="/tmp",
    )
    assert res.returncode == 0, f"validator exited {res.returncode}: {res.stderr}"
    assert res.stdout in (expected, expected + "\n"), repr(res.stdout)


def expected_result(types, parents):
    for start, backup_type in types.items():
        if backup_type != "Differential":
            continue
        current = start
        seen = set()
        while True:
            if current in seen:
                return "INVALID"
            seen.add(current)
            current_type = types.get(current)
            if current_type == "Full":
                break
            if current_type != "Differential":
                return "INVALID"
            parent = parents.get(current)
            if parent is None:
                return "INVALID"
            current = parent
    return "VALID"


def write_manifest(path, types, parents, rng):
    nodes = list(types)
    rng.shuffle(nodes)
    blocks = ["@prefix db: <http://example.org/db/> .\n"]
    for node in nodes:
        predicates = [f'db:backupType "{types[node]}"']
        if node in parents:
            predicates.append(f"db:dependsOn db:{parents[node]}")
        blocks.append(
            f"db:{node} a db:Backup ;\n    "
            + " ;\n    ".join(predicates)
            + " .\n"
        )
    path.write_text("\n".join(blocks), encoding="utf-8")


def test_validator_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Validator script is missing at {SCRIPT_PATH}"


def test_vendored_rdflib_was_fixed_and_installed():
    vendor_init = Path("/app/vendor/rdflib/rdflib/__init__.py")
    vendor_setup = Path("/app/vendor/rdflib/setup.py")
    assert vendor_init.is_file()
    assert vendor_setup.is_file()
    assert "missing_sys_module_xyz_broken" not in vendor_init.read_text(encoding="utf-8")
    assert "missing_sys_module_xyz_broken" not in vendor_setup.read_text(encoding="utf-8")

    probe = subprocess.run(
        [
            "python3",
            "-c",
            "import importlib.metadata as m, rdflib; "
            "print(rdflib.__version__); print(rdflib.__file__); print(m.version('rdflib'))",
        ],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert probe.returncode == 0, probe.stderr
    lines = probe.stdout.strip().splitlines()
    assert len(lines) == 3, probe.stdout
    assert lines[0] == "6.2.0"
    assert lines[2] == "6.2.0"
    installed_init = Path(lines[1]).resolve()
    assert installed_init.is_file()
    assert installed_init.read_bytes() == vendor_init.read_bytes()


def test_adversarial_corpus_validation():
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.ttl"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.ttl"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    clean_failures = []
    for f in clean_files:
        res = subprocess.run(["python3", SCRIPT_PATH, f], capture_output=True, text=True)
        output = res.stdout.strip()
        if output != "VALID":
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        res = subprocess.run(["python3", SCRIPT_PATH, f], capture_output=True, text=True)
        output = res.stdout.strip()
        if output != "INVALID":
            evil_failures.append(os.path.basename(f))

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_manifests_at_unpredictable_paths():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = []

    # Guaranteed coverage of direct/full chains, cycles, dead ends, and disconnected components.
    cases.extend([
        ({"a": "Full"}, {}),
        ({"a": "Differential", "b": "Full"}, {"a": "b"}),
        ({"a": "Differential", "b": "Differential", "c": "Full"}, {"a": "b", "b": "c"}),
        ({"a": "Differential", "b": "Differential"}, {"a": "b", "b": "a"}),
        ({"a": "Differential"}, {}),
        ({"a": "Differential", "b": "Full"}, {"a": "undeclared"}),
        ({"a": "Full", "b": "Differential", "c": "Differential"}, {"b": "a"}),
    ])

    for _ in range(35):
        count = rng.randint(2, 12)
        names = ["n" + uuid.uuid4().hex for _ in range(count)]
        types = {name: rng.choice(["Full", "Differential"]) for name in names}
        parents = {}
        for name in names:
            if types[name] == "Differential":
                choice = rng.randrange(count + 3)
                if choice < count:
                    parents[name] = names[choice]
                elif choice == count:
                    parents[name] = "missing" + uuid.uuid4().hex
        cases.append((types, parents))

    with tempfile.TemporaryDirectory(prefix="rdf-check-") as td:
        root = Path(td)
        rng.shuffle(cases)
        observed = set()
        for index, (types, parents) in enumerate(cases):
            expected = expected_result(types, parents)
            observed.add(expected)
            path = root / f"manifest-{uuid.uuid4().hex}-{index}.ttl"
            write_manifest(path, types, parents, rng)
            run_validator(path, expected)
        assert observed == {"VALID", "INVALID"}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
