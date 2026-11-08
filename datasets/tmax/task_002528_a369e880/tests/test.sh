#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import runpy
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime, timedelta
from importlib.machinery import EXTENSION_SUFFIXES, ExtensionFileLoader


def verify_vendored_package():
    package_dir = "/app/fast_log_tokenizer-0.1"
    setup_path = os.path.join(package_dir, "setup.py")
    source_path = os.path.join(package_dir, "tokenizer.c")
    assert os.path.isfile(setup_path), f"Missing vendored setup.py at {setup_path}"
    assert os.path.isfile(source_path), f"Missing tokenizer source at {source_path}"

    # Inspect the actual setup configuration, allowing harmless stylistic changes.
    import setuptools
    captured = {}
    original_setup = setuptools.setup
    original_cwd = os.getcwd()

    def capture_setup(*args, **kwargs):
        captured.update(kwargs)

    try:
        setuptools.setup = capture_setup
        os.chdir(package_dir)
        runpy.run_path(setup_path, run_name="__main__")
    finally:
        os.chdir(original_cwd)
        setuptools.setup = original_setup

    extensions = captured.get("ext_modules") or []
    matching = [ext for ext in extensions if getattr(ext, "name", None) == "fast_log_tokenizer"]
    assert matching, "setup.py does not configure the fast_log_tokenizer extension"
    configured_sources = [os.path.normpath(src) for ext in matching for src in ext.sources]
    assert any(os.path.basename(src) == "tokenizer.c" for src in configured_sources), \
        f"setup.py still does not build tokenizer.c: {configured_sources}"
    for src in configured_sources:
        full_path = src if os.path.isabs(src) else os.path.join(package_dir, src)
        assert os.path.isfile(full_path), f"Configured extension source does not exist: {src}"

    # Confirm the repaired vendored package itself can build.
    build_root = "/tmp/verifier_tokenizer_build"
    shutil.rmtree(build_root, ignore_errors=True)
    result = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--force",
         "--build-temp", os.path.join(build_root, "temp"),
         "--build-lib", os.path.join(build_root, "lib")],
        cwd=package_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120
    )
    assert result.returncode == 0, f"Repaired vendored tokenizer does not build:\n{result.stdout}"

    # Use isolated mode so a local Python shim cannot masquerade as installation.
    probe = r'''
import json
import importlib.metadata
from importlib.machinery import ExtensionFileLoader, EXTENSION_SUFFIXES
import fast_log_tokenizer
path = getattr(fast_log_tokenizer, "__file__", "")
loader_ok = isinstance(fast_log_tokenizer.__loader__, ExtensionFileLoader)
suffix_ok = any(path.endswith(s) for s in EXTENSION_SUFFIXES)
dist = importlib.metadata.distribution("fast_log_tokenizer")
files = [str(p) for p in (dist.files or [])]
print(json.dumps({
    "path": path,
    "loader_ok": loader_ok,
    "suffix_ok": suffix_ok,
    "version": dist.version,
    "dist_has_extension": any(any(p.endswith(s) for s in EXTENSION_SUFFIXES) for p in files),
    "tokens": fast_log_tokenizer.tokenize("Hello  EN World\\tX "),
    "empty": fast_log_tokenizer.tokenize("")
}))
'''
    result = subprocess.run(
        [sys.executable, "-I", "-c", probe],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"fast_log_tokenizer is not installed:\n{result.stderr}"
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert info["loader_ok"] and info["suffix_ok"], \
        f"Installed fast_log_tokenizer is not a native extension: {info['path']}"
    assert info["dist_has_extension"], "Installed distribution does not contain the extension module"
    assert info["tokens"] == ["Hello", "EN", "World\\tX"], \
        f"Installed tokenizer behaves incorrectly: {info['tokens']}"
    assert info["empty"] == [], "Installed tokenizer handles empty input incorrectly"


def find_processing_scripts():
    roots = ["/home/user", "/app", "/root", "/tmp", "/workspace"]
    excluded = {
        os.path.realpath("/tmp/test_final_state.py"),
        os.path.realpath("/tmp/verifier_tokenizer_instrument/sitecustomize.py"),
    }
    candidates = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            real_dir = os.path.realpath(directory)
            if real_dir.startswith(os.path.realpath("/app/fast_log_tokenizer-0.1")):
                subdirs[:] = []
                continue
            subdirs[:] = [d for d in subdirs if d not in {".git", "__pycache__", "node_modules"}]
            for name in files:
                path = os.path.join(directory, name)
                real_path = os.path.realpath(path)
                if real_path in excluded or not os.path.isfile(path):
                    continue
                try:
                    if os.path.getsize(path) > 2_000_000:
                        continue
                    with open(path, "rb") as f:
                        prefix = f.read(256)
                    is_python = name.endswith(".py") or (
                        prefix.startswith(b"#!") and b"python" in prefix.splitlines()[0].lower()
                    )
                    if not is_python:
                        continue
                    with open(path, "r", encoding="utf-8", errors="ignore") as f:
                        source = f.read()
                    if "fast_log_tokenizer" in source and "tokenize" in source:
                        candidates.append(path)
                except OSError:
                    continue
    return sorted(set(candidates))


def run_submitted_pipeline_with_instrumentation(raw_records):
    processed_path = "/home/user/processed_logs.jsonl"
    raw_path = "/home/user/raw_logs.jsonl"
    candidates = find_processing_scripts()
    assert candidates, "No Python processing script using fast_log_tokenizer was found"

    instrument_dir = "/tmp/verifier_tokenizer_instrument"
    shutil.rmtree(instrument_dir, ignore_errors=True)
    os.makedirs(instrument_dir)
    calls_path = os.path.join(instrument_dir, "calls.jsonl")
    marker = "__verifier_tokenizer_probe_91c7__"
    sitecustomize = f'''
import json
import os
import fast_log_tokenizer
_original_tokenize = fast_log_tokenizer.tokenize
_marker = {marker!r}
_calls_path = os.environ.get("TOKENIZER_CALL_LOG")
def _verified_tokenize(text):
    if _calls_path:
        with open(_calls_path, "a", encoding="utf-8") as _f:
            _f.write(json.dumps(text) + "\\n")
    return [_marker] + _original_tokenize(text)
fast_log_tokenizer.tokenize = _verified_tokenize
'''
    with open(os.path.join(instrument_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    with open(raw_path, "rb") as f:
        original_raw = f.read()
    original_processed = None
    if os.path.exists(processed_path):
        with open(processed_path, "rb") as f:
            original_processed = f.read()

    successful_script = None
    failures = []
    for script in candidates:
        try:
            with open(raw_path, "wb") as f:
                f.write(original_raw)
            if os.path.exists(processed_path):
                os.remove(processed_path)
            if os.path.exists(calls_path):
                os.remove(calls_path)

            env = os.environ.copy()
            env["PYTHONPATH"] = instrument_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
            env["TOKENIZER_CALL_LOG"] = calls_path
            result = subprocess.run(
                [sys.executable, script], cwd=os.path.dirname(script) or "/",
                env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, timeout=180
            )
            if result.returncode != 0 or not os.path.isfile(processed_path):
                failures.append(f"{script}: exit {result.returncode}")
                continue

            with open(processed_path) as f:
                instrumented = [json.loads(line) for line in f if line.strip()]
            if len(instrumented) != 1000:
                failures.append(f"{script}: produced {len(instrumented)} records under instrumentation")
                continue
            if any(marker not in rec.get("tokens", []) for rec in instrumented):
                failures.append(f"{script}: output was not derived from tokenizer return values")
                continue

            with open(calls_path) as f:
                called_messages = Counter(json.loads(line) for line in f if line.strip())
            needed_messages = Counter(raw_records[rec.get("id")]["msg"] for rec in instrumented
                                      if rec.get("id") in raw_records)
            if any(called_messages[msg] < count for msg, count in needed_messages.items()):
                failures.append(f"{script}: did not tokenize each sampled record's message")
                continue

            # Run the same demonstrated pipeline normally to produce the artifact tested below.
            if os.path.exists(processed_path):
                os.remove(processed_path)
            normal_env = os.environ.copy()
            normal_env.pop("TOKENIZER_CALL_LOG", None)
            result = subprocess.run(
                [sys.executable, script], cwd=os.path.dirname(script) or "/",
                env=normal_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, timeout=180
            )
            if result.returncode == 0 and os.path.isfile(processed_path):
                successful_script = script
                break
            failures.append(f"{script}: normal execution failed with exit {result.returncode}")
        except Exception as exc:
            failures.append(f"{script}: {exc}")

    with open(raw_path, "wb") as f:
        f.write(original_raw)
    if successful_script is None:
        if original_processed is not None:
            with open(processed_path, "wb") as f:
                f.write(original_processed)
        raise AssertionError("No submitted Python pipeline both used the tokenizer and produced the output. " + "; ".join(failures))


def test_processed_logs_metric():
    raw_logs_path = "/home/user/raw_logs.jsonl"
    processed_logs_path = "/home/user/processed_logs.jsonl"

    assert os.path.exists(raw_logs_path), f"Raw logs missing at {raw_logs_path}"
    verify_vendored_package()

    import fast_log_tokenizer
    assert isinstance(fast_log_tokenizer.__loader__, ExtensionFileLoader)
    assert any(fast_log_tokenizer.__file__.endswith(s) for s in EXTENSION_SUFFIXES)

    raw_data = {}
    raw_lang_counts = Counter()
    total_raw = 0

    with open(raw_logs_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            rec_id = record["id"]
            lang = record["lang"]
            msg = record["msg"]

            dt = datetime(2023, 1, 1) + timedelta(minutes=rec_id)
            expected_ts = dt.strftime("%Y-%m-%dT%H:%M:%SZ")

            # Preserve the original check and additionally derive the expected result
            # from the installed extension required by the task.
            expected_tokens = [t.lower() for t in msg.split() if t.strip()]
            tokenizer_tokens = [t.lower() for t in fast_log_tokenizer.tokenize(msg)
                                if t and not t.isspace()]

            raw_data[rec_id] = {
                "lang": lang,
                "msg": msg,
                "expected_ts": expected_ts,
                "expected_tokens": expected_tokens,
                "tokenizer_tokens": tokenizer_tokens,
            }
            raw_lang_counts[lang] += 1
            total_raw += 1

    run_submitted_pipeline_with_instrumentation(raw_data)
    assert os.path.exists(processed_logs_path), f"Processed logs missing at {processed_logs_path}"

    raw_props = {k: v / total_raw for k, v in raw_lang_counts.items()}

    processed_records = []
    with open(processed_logs_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            processed_records.append(json.loads(line))

    assert len(processed_records) == 1000, \
        f"Expected exactly 1000 records in processed logs, got {len(processed_records)}"

    # A sample must contain 1,000 distinct source records, not repeated copies.
    processed_ids = [rec.get("id") for rec in processed_records]
    assert len(set(processed_ids)) == 1000, "Sampled record IDs must be unique"

    proc_lang_counts = Counter(r.get("lang") for r in processed_records)
    total_proc = len(processed_records)
    proc_props = {k: v / total_proc for k, v in proc_lang_counts.items()}

    all_langs = set(raw_props.keys()).union(set(proc_props.keys()))
    max_diff = 0.0
    for lang in all_langs:
        diff = abs(raw_props.get(lang, 0.0) - proc_props.get(lang, 0.0))
        if diff > max_diff:
            max_diff = diff

    assert max_diff < 0.02, f"Language distribution mismatch. Max absolute difference is {max_diff:.4f}, which is >= 0.02. Raw: {raw_props}, Processed: {proc_props}"

    valid_count = 0
    for rec in processed_records:
        rec_id = rec.get("id")
        if rec_id not in raw_data:
            continue

        expected = raw_data[rec_id]
        if rec.get("timestamp") != expected["expected_ts"]:
            continue
        if rec.get("lang") != expected["lang"]:
            continue
        if rec.get("tokens") != expected["expected_tokens"]:
            continue
        if rec.get("tokens") != expected["tokenizer_tokens"]:
            continue

        valid_count += 1

    valid_proportion = valid_count / total_proc
    assert valid_proportion >= 0.95, f"Valid Sample Proportion is {valid_proportion:.4f}, which is below the threshold of 0.95. {valid_count} out of {total_proc} records were perfectly processed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
