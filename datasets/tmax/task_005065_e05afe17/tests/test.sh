#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import shutil
import subprocess
import tempfile
import uuid


def run_filter(path):
    return subprocess.run(
        ["/home/user/filter", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def is_compliant_json(path):
    try:
        with open(path, "r", encoding="utf-8") as fp:
            data = json.load(fp)
        return (
            isinstance(data, dict)
            and isinstance(data.get("tags"), list)
            and "CostCenter=FinOps" in data["tags"]
        )
    except Exception:
        return False


def test_filter_executable_exists():
    assert os.path.isfile('/home/user/filter'), "The C++ filter binary is missing at /home/user/filter."
    assert os.access('/home/user/filter', os.X_OK), "The C++ filter binary is not executable."
    assert os.path.isfile('/home/user/filter.cpp'), "The C++ source is missing at /home/user/filter.cpp."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    filter_bin = "/home/user/filter"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for f in clean_files:
        res = subprocess.run([filter_bin, f], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        res = subprocess.run([filter_bin, f], capture_output=True)
        if res.returncode == 0:
            evil_failed.append(os.path.basename(f))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")

    assert not error_msgs, "Adversarial corpus verification failed: " + " | ".join(error_msgs)


def test_filter_on_generated_inputs():
    token = uuid.uuid4().hex
    cases = [
        ({"deployment": token, "tags": ["CostCenter=FinOps"]}, 0),
        ({"tags": ["Env=Dev", "CostCenter=FinOps", token], "metadata": {"x": 1}}, 0),
        ({"tags": [token, "CostCenter=R&D"]}, 1),
        ({"tags": ["costcenter=FinOps", token]}, 1),
        ({"tags": ["CostCenter=FinOps-extra", token]}, 1),
        ({"tags": "CostCenter=FinOps", "nonce": token}, 1),
        ({"tags": None, "description": "CostCenter=FinOps", "nonce": token}, 1),
        ({"metadata": {"tags": ["CostCenter=FinOps"]}, "nonce": token}, 1),
        ([{"tags": ["CostCenter=FinOps"], "nonce": token}], 1),
        ({"tags": [{"name": "CostCenter=FinOps"}], "nonce": token}, 1),
        ({"nonce": token}, 1),
    ]
    malformed = [
        '{"tags":["CostCenter=FinOps"],"nonce":"' + token + '"',
        'not-json CostCenter=FinOps ' + token,
        '{"tags": ["CostCenter=FinOps",], "nonce": "' + token + '"}',
    ]

    with tempfile.TemporaryDirectory(prefix="classifier_cases_") as td:
        generated = []
        for index, (value, expected) in enumerate(cases):
            path = os.path.join(td, f"sample_{uuid.uuid4().hex}_{index}.json")
            with open(path, "w", encoding="utf-8") as fp:
                json.dump(value, fp)
            generated.append((path, expected))
        for index, text in enumerate(malformed):
            path = os.path.join(td, f"sample_{uuid.uuid4().hex}_bad_{index}.json")
            with open(path, "w", encoding="utf-8") as fp:
                fp.write(text)
            generated.append((path, 1))

        for path, expected in generated:
            result = run_filter(path)
            assert result.returncode == expected, (
                f"filter returned {result.returncode}, expected {expected}, for generated input "
                f"{os.path.basename(path)}; stderr={result.stderr.decode(errors='replace')}"
            )


def test_pipeline_script():
    pipeline_script = "/home/user/pipeline.sh"
    source = "/home/user/filter.cpp"
    binary = "/home/user/filter"
    assert os.path.isfile(pipeline_script), f"{pipeline_script} is missing."
    assert os.path.isfile(source), f"{source} is missing."

    # Add an unpredictable marker to the source, then remove the existing binary.
    # The resulting executable must contain this marker, proving that pipeline.sh
    # actually rebuilt filter.cpp rather than merely retaining a submitted binary.
    marker_id = uuid.uuid4().hex
    marker = f"PIPELINE_COMPILE_MARKER_{marker_id}"
    with open(source, "a", encoding="utf-8") as fp:
        fp.write(
            f'\nextern "C" __attribute__((used)) const char verifier_marker_{marker_id}[] = "{marker}";\n'
        )
    if os.path.lexists(binary):
        os.remove(binary)

    approved_dir = "/home/user/approved_deployments"
    if os.path.lexists(approved_dir):
        if os.path.isdir(approved_dir) and not os.path.islink(approved_dir):
            shutil.rmtree(approved_dir)
        else:
            os.remove(approved_dir)

    raw_dir = "/app/corpus/raw"
    added = []
    generated_values = [
        {"id": marker_id, "tags": ["CostCenter=FinOps", "Generated=True"]},
        {"id": marker_id, "tags": ["CostCenter=Other"]},
        {"id": marker_id, "metadata": {"tags": ["CostCenter=FinOps"]}},
    ]
    try:
        for value in generated_values:
            path = os.path.join(raw_dir, f"generated_{uuid.uuid4().hex}.json")
            with open(path, "w", encoding="utf-8") as fp:
                json.dump(value, fp)
            added.append(path)
        malformed_path = os.path.join(raw_dir, f"generated_{uuid.uuid4().hex}.json")
        with open(malformed_path, "w", encoding="utf-8") as fp:
            fp.write('{"tags":["CostCenter=FinOps"], broken}')
        added.append(malformed_path)

        res = subprocess.run(["bash", pipeline_script], capture_output=True, timeout=30)
        assert res.returncode == 0, (
            f"pipeline.sh failed with exit code {res.returncode}. "
            f"stderr: {res.stderr.decode(errors='replace')}"
        )

        assert os.path.isfile(binary), "pipeline.sh did not create /home/user/filter."
        assert os.access(binary, os.X_OK), "The rebuilt filter is not executable."
        with open(binary, "rb") as fp:
            rebuilt = fp.read()
        assert rebuilt.startswith(b"\x7fELF"), "pipeline.sh did not produce a compiled executable."
        assert marker.encode() in rebuilt, "pipeline.sh did not compile the current /home/user/filter.cpp."

        assert os.path.isdir(approved_dir), f"{approved_dir} was not created."

        raw_files = glob.glob(os.path.join(raw_dir, "*.json"))
        valid_raw_files = [f for f in raw_files if is_compliant_json(f)]
        expected = {os.path.basename(f): os.path.realpath(f) for f in valid_raw_files}

        entries = {
            name: os.path.join(approved_dir, name)
            for name in os.listdir(approved_dir)
            if name.endswith(".json")
        }
        assert len(entries) == len(valid_raw_files), (
            f"Expected {len(valid_raw_files)} symlinks, found {len(entries)}."
        )
        assert set(entries) == set(expected), (
            f"Approved filenames differ from compliant raw files: "
            f"missing={sorted(set(expected) - set(entries))}, "
            f"extra={sorted(set(entries) - set(expected))}"
        )

        for name, sl in entries.items():
            assert os.path.islink(sl), f"{sl} is not a symbolic link."
            target = os.readlink(sl)
            assert os.path.isabs(target) or os.path.exists(os.path.join(approved_dir, target)), f"Broken symlink {sl}"
            assert os.path.exists(sl), f"Broken symlink {sl}"
            assert os.path.realpath(sl) == expected[name], (
                f"{sl} points to {os.path.realpath(sl)}, expected {expected[name]}"
            )

        # Exercise the binary produced by the pipeline on an unpredictable file.
        probe = os.path.join(raw_dir, f"probe_{uuid.uuid4().hex}.json")
        try:
            with open(probe, "w", encoding="utf-8") as fp:
                json.dump({"nonce": uuid.uuid4().hex, "tags": ["CostCenter=FinOps"]}, fp)
            assert run_filter(probe).returncode == 0
            with open(probe, "w", encoding="utf-8") as fp:
                fp.write('{"tags":["CostCenter=FinOps"] trailing')
            assert run_filter(probe).returncode == 1
        finally:
            if os.path.exists(probe):
                os.remove(probe)
    finally:
        for path in added:
            if os.path.exists(path):
                os.remove(path)


def test_expect_script():
    expect_script = "/home/user/auto_deploy.exp"
    assert os.path.isfile(expect_script), f"{expect_script} is missing."

    res = subprocess.run(["expect", expect_script], capture_output=True, timeout=15)
    assert res.returncode == 0, (
        f"auto_deploy.exp failed with exit code {res.returncode}. "
        f"Output: {res.stdout.decode(errors='replace')} {res.stderr.decode(errors='replace')}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
