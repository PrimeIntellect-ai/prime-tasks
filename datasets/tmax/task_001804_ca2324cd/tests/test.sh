#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

FILTER = "/home/user/filter.py"
PIPELINE = "/home/user/pipeline.sh"
SOURCE_ROOT = "/app/dictdiffer-0.9.0"


def run_filter(path):
    return subprocess.run(["python3", FILTER, path], capture_output=True, text=True)


def test_dictdiffer_fixed_and_vendored_source_repaired():
    init_file = os.path.join(SOURCE_ROOT, "dictdiffer", "__init__.py")
    assert os.path.isfile(init_file), "Vendored dictdiffer source is missing"
    with open(init_file, "r", encoding="utf-8") as f:
        source = f.read()
    assert 'raise ImportError("Missing required dependency: dummy_dep")' not in source

    # Import directly from the vendored tree, without site-packages, to ensure that
    # the requested source tree itself was repaired.
    source_check = subprocess.run(
        [
            "python3", "-S", "-c",
            "import dictdiffer; "
            "assert list(dictdiffer.diff({'a': 1}, {'a': 2})) == "
            "[('change', 'a', (1, 2))]"
        ],
        cwd=SOURCE_ROOT,
        capture_output=True,
        text=True,
    )
    assert source_check.returncode == 0, source_check.stderr

    try:
        import dictdiffer
    except ImportError as e:
        pytest.fail(f"Failed to import installed dictdiffer: {e}")

    assert list(dictdiffer.diff({'a': 1}, {'a': 2})) == [
        ('change', 'a', (1, 2))
    ]
    assert list(dictdiffer.diff({'a': 1}, {'a': 1, 'b': 2, 'c': 3})) == [
        ('add', '', [('b', 2), ('c', 3)])
    ]
    assert list(dictdiffer.diff({'x': {'a': 1}}, {'x': {'a': 2}})) == [
        ('change', 'x.a', (1, 2))
    ]


def test_filter_script_corpora():
    assert os.path.isfile(FILTER), f"Filter script not found at {FILTER}"

    clean_files = glob.glob("/app/corpora/clean/*")
    evil_files = glob.glob("/app/corpora/evil/*")

    clean_failures = [
        os.path.basename(path) for path in clean_files
        if run_filter(path).returncode != 0
    ]
    evil_failures = [
        os.path.basename(path) for path in evil_files
        if run_filter(path).returncode != 1
    ]

    errors = []
    if evil_failures:
        errors.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_failures)
        )
    if clean_failures:
        errors.append(
            f"{len(clean_failures)} of {len(clean_files)} clean rejected: "
            + ", ".join(clean_failures)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def test_filter_generated_policy_cases(tmp_path):
    nonce = secrets.token_hex(12)
    base = {
        "server_id": "srv-" + nonce,
        "timestamp": 731,
        "pre_install": "echo ready",
        "post_install": "systemctl restart app",
        "file_path": "/etc/app_config/" + nonce + ".conf",
        "env": {"PORT": "8123", "MODE": "prod"},
        # Policy strings outside the specified fields must not cause rejection.
        "description": "documentation mentions bash and /bin/sh",
    }

    cases = []
    cases.append(("clean-base", dict(base), 0))

    clean_case = dict(base)
    clean_case["pre_install"] = "BASH /bin/zsh"
    clean_case["env"] = {"XLD_TEST": "ok", "PATH": "/bin"}
    cases.append(("clean-near-misses", clean_case, 0))

    evil_sh = dict(base)
    evil_sh["post_install"] = "prefix /bin/sh suffix " + nonce
    cases.append(("evil-sh", evil_sh, 1))

    evil_bash = dict(base)
    evil_bash["pre_install"] = "run-bash-now-" + nonce
    cases.append(("evil-bash", evil_bash, 1))

    evil_path = dict(base)
    evil_path["file_path"] = "/etc/app_config_evil/" + nonce
    cases.append(("evil-path", evil_path, 1))

    evil_env = dict(base)
    evil_env["env"] = {"PORT": "8123", "LD_" + nonce: "payload"}
    cases.append(("evil-env", evil_env, 1))

    for index, (label, payload, expected) in enumerate(cases):
        path = tmp_path / f"{nonce}-{index}-{label}.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        result = run_filter(str(path))
        assert result.returncode == expected, (
            f"Generated case {label} returned {result.returncode}, expected {expected}. "
            f"stderr={result.stderr!r}"
        )

    malformed = tmp_path / f"{nonce}-malformed.json"
    malformed.write_text('{"server_id": ', encoding="utf-8")
    assert run_filter(str(malformed)).returncode == 1


def test_pipeline_execution_and_log():
    assert os.path.isfile(PIPELINE), f"Pipeline script not found at {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Pipeline script {PIPELINE} is not executable"

    log_file = "/home/user/pipeline.log"
    if os.path.exists(log_file):
        os.remove(log_file)

    result = subprocess.run([PIPELINE], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.exists(log_file), "Pipeline log was not created"
    with open(log_file, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    with open("/app/baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)

    import dictdiffer
    expected_warns = []
    clean_configs = {}
    for path in sorted(glob.glob("/app/incoming_configs/*.json")):
        classification = run_filter(path).returncode
        if classification == 1:
            expected_warns.append(f"[WARN] Rejected {path}")
        elif classification == 0:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            sid = data.get("server_id")
            timestamp = data.get("timestamp", 0)
            if sid not in clean_configs or timestamp > clean_configs[sid]["timestamp"]:
                clean_configs[sid] = {"timestamp": timestamp, "data": data}

    expected_infos = []
    for sid, config in clean_configs.items():
        count = len(list(dictdiffer.diff(baseline, config["data"])))
        expected_infos.append(f"[INFO] Processed {sid} with {count} changes")

    actual_set = set(actual_lines)
    expected_set = set(expected_warns + expected_infos)
    assert actual_set == expected_set, (
        f"Log contents mismatch. Missing={expected_set - actual_set}; "
        f"extra={actual_set - expected_set}"
    )


def test_pipeline_on_generated_inputs_and_uses_filter_and_differ(tmp_path):
    nonce = secrets.token_hex(10)
    incoming = "/app/incoming_configs"
    baseline_path = "/app/baseline.json"
    log_path = "/home/user/pipeline.log"

    incoming_backup = str(tmp_path / "incoming-backup")
    filter_backup = str(tmp_path / "submitted-filter.py")
    baseline_backup = (tmp_path / "baseline-backup.json")
    marker_filter = str(tmp_path / "filter-calls.txt")
    marker_diff = str(tmp_path / "diff-calls.txt")
    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()

    shutil.move(incoming, incoming_backup)
    os.mkdir(incoming)
    shutil.copy2(FILTER, filter_backup)
    shutil.copy2(baseline_path, baseline_backup)

    try:
        # The wrapper delegates classification to the submitted sanitizer while
        # proving that the pipeline actually invokes it for every input.
        wrapper = f'''#!/usr/bin/env python3
import os, sys
with open({marker_filter!r}, "a", encoding="utf-8") as f:
    f.write(os.path.abspath(sys.argv[1]) + "\\n")
os.execv(sys.executable, [sys.executable, {filter_backup!r}, sys.argv[1]])
'''
        with open(FILTER, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(FILTER, 0o755)

        # This compatible differ shim records imports/calls and independently
        # yields one tuple for every changed leaf in the same-shaped test data.
        shim = f'''import os

def diff(first, second):
    with open(os.environ["DD_MARKER"], "a", encoding="utf-8") as f:
        f.write("called\\n")
    def walk(a, b, path=""):
        if isinstance(a, dict) and isinstance(b, dict):
            for key in sorted(a):
                child = str(key) if not path else path + "." + str(key)
                yield from walk(a[key], b[key], child)
        elif a != b:
            yield ("change", path, (a, b))
    yield from walk(first, second)
'''
        (shim_dir / "dictdiffer.py").write_text(shim, encoding="utf-8")

        baseline = {
            "server_id": "base-" + nonce,
            "timestamp": 0,
            "pre_install": "echo base",
            "post_install": "restart base",
            "file_path": "/etc/app_config/base.conf",
            "env": {"MODE": "prod", "PORT": "8000"},
        }
        with open(baseline_path, "w", encoding="utf-8") as f:
            json.dump(baseline, f)

        sid_a = "alpha-" + nonce
        sid_b = "beta-" + nonce
        configs = {
            f"low-{nonce}.json": {
                **baseline, "server_id": sid_a, "timestamp": 10,
                "pre_install": "echo old", "env": {"MODE": "prod", "PORT": "8001"},
            },
            f"high-{nonce}.json": {
                **baseline, "server_id": sid_a, "timestamp": 99,
                "pre_install": "echo newest", "env": {"MODE": "prod", "PORT": "8999"},
            },
            f"other-{nonce}.json": {
                **baseline, "server_id": sid_b, "timestamp": 44,
                "post_install": "restart changed",
                "file_path": "/etc/app_config/other.conf",
            },
            f"bad-hook-{nonce}.json": {
                **baseline, "server_id": "bad1-" + nonce, "timestamp": 3,
                "pre_install": "x/bin/sh y",
            },
            f"bad-env-{nonce}.json": {
                **baseline, "server_id": "bad2-" + nonce, "timestamp": 4,
                "env": {"MODE": "prod", "LD_X": nonce},
            },
            f"bad-path-{nonce}.json": {
                **baseline, "server_id": "bad3-" + nonce, "timestamp": 5,
                "file_path": "/tmp/" + nonce,
            },
        }
        paths = []
        for name, data in configs.items():
            path = os.path.join(incoming, name)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f)
            paths.append(path)

        if os.path.exists(log_path):
            os.remove(log_path)

        env = os.environ.copy()
        env["PYTHONPATH"] = str(shim_dir) + os.pathsep + env.get("PYTHONPATH", "")
        env["DD_MARKER"] = marker_diff
        result = subprocess.run(
            [PIPELINE], cwd=str(tmp_path), env=env, capture_output=True, text=True
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(log_path)

        with open(log_path, "r", encoding="utf-8") as f:
            actual = {line.strip() for line in f if line.strip()}

        expected = {
            f"[WARN] Rejected {os.path.join(incoming, f'bad-hook-{nonce}.json')}",
            f"[WARN] Rejected {os.path.join(incoming, f'bad-env-{nonce}.json')}",
            f"[WARN] Rejected {os.path.join(incoming, f'bad-path-{nonce}.json')}",
            f"[INFO] Processed {sid_a} with 4 changes",
            f"[INFO] Processed {sid_b} with 4 changes",
        }
        assert actual == expected, f"Expected {expected}, got {actual}"

        with open(marker_filter, "r", encoding="utf-8") as f:
            filter_calls = {line.strip() for line in f if line.strip()}
        assert filter_calls == set(paths), "Pipeline did not run filter.py on every JSON file"

        with open(marker_diff, "r", encoding="utf-8") as f:
            diff_calls = [line for line in f if line.strip()]
        assert len(diff_calls) == 2, (
            "Pipeline must invoke dictdiffer once for each deduplicated clean server"
        )
    finally:
        if os.path.exists(incoming):
            shutil.rmtree(incoming)
        shutil.move(incoming_backup, incoming)
        shutil.copy2(filter_backup, FILTER)
        shutil.copy2(baseline_backup, baseline_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
