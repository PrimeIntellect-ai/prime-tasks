#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import subprocess
import tempfile

SCRIPT = "/home/user/etl.py"
ORIGINAL_INPUT = "/home/user/input"
ORIGINAL_OUTPUT = "/home/user/output"
LOG_PATH = "/home/user/pipeline.log"


def run_etl(input_dir, output_dir, env=None):
    result = subprocess.run(
        ["python3", SCRIPT, input_dir, output_dir],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"etl.py failed to execute. Stderr: {result.stderr}"


def test_etl_script_exists():
    assert os.path.isfile(SCRIPT), "The script /home/user/etl.py does not exist."


def test_etl_uses_multiprocessing():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        code = f.read()

    tree = ast.parse(code)
    imports = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append(node.module)

    has_parallel_lib = any(
        imp.startswith("multiprocessing") or imp.startswith("concurrent.futures")
        for imp in imports
    )
    assert has_parallel_lib, "The script must use 'multiprocessing' or 'concurrent.futures' for parallel processing."


def test_etl_execution_and_idempotency():
    os.makedirs(ORIGINAL_OUTPUT, exist_ok=True)
    summary_path = os.path.join(ORIGINAL_OUTPUT, "summary.txt")
    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("stale output that must be overwritten\n")
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    run_etl(ORIGINAL_INPUT, ORIGINAL_OUTPUT)
    with open(summary_path, "rb") as f:
        first = f.read()

    run_etl(ORIGINAL_INPUT, ORIGINAL_OUTPUT)
    with open(summary_path, "rb") as f:
        second = f.read()

    assert first == second, "Rerunning the ETL did not produce exactly the same summary.txt."


def test_output_summary_content():
    summary_path = "/home/user/output/summary.txt"
    assert os.path.isfile(summary_path), f"The output file {summary_path} does not exist."

    with open(summary_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "Hour: 2023-10-01T10:00:00Z | Unique Langs: 2 | Sample: Hello",
        "Hour: 2023-10-01T11:00:00Z | Unique Langs: 2 | Sample: Bonjour",
        "Hour: 2023-10-02T08:00:00Z | Unique Langs: 1 | Sample: مرحبا",
    ]
    actual_lines = content.split("\n")
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in summary.txt, found {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual.strip()}'"


def test_pipeline_log_content():
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Total unique records: 5" in content, "The log file does not contain the expected 'Total unique records: 5' message."


def test_dynamic_inputs_parallel_use_and_idempotency():
    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, "input")
        output_dir = os.path.join(root, "output")
        hooks_dir = os.path.join(root, "hooks")
        marker = os.path.join(root, "parallel.marker")
        os.makedirs(input_dir)
        os.makedirs(hooks_dir)

        hook = r'''
import os

def _record(kind, amount=1):
    path = os.environ.get("ETL_PARALLEL_MARKER")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write("%s:%s\n" % (kind, amount))

try:
    import concurrent.futures as _cf
    for _cls in (_cf.ThreadPoolExecutor, _cf.ProcessPoolExecutor):
        _old_submit = _cls.submit
        _old_map = _cls.map
        def _make_submit(old):
            def submit(self, *args, **kwargs):
                _record("executor_submit", 1)
                return old(self, *args, **kwargs)
            return submit
        def _make_map(old):
            def map_method(self, fn, *iterables, **kwargs):
                materialized = [list(x) for x in iterables]
                amount = min([len(x) for x in materialized] or [0])
                _record("executor_map", amount)
                return old(self, fn, *materialized, **kwargs)
            return map_method
        _cls.submit = _make_submit(_old_submit)
        _cls.map = _make_map(_old_map)
except Exception:
    pass

try:
    import multiprocessing.pool as _mp_pool
    for _name in ("map", "starmap", "imap", "imap_unordered"):
        if hasattr(_mp_pool.Pool, _name):
            _old = getattr(_mp_pool.Pool, _name)
            def _make_pool_map(old):
                def pool_map(self, func, iterable, *args, **kwargs):
                    values = list(iterable)
                    _record("pool_map", len(values))
                    return old(self, func, values, *args, **kwargs)
                return pool_map
            setattr(_mp_pool.Pool, _name, _make_pool_map(_old))
    if hasattr(_mp_pool.Pool, "apply_async"):
        _old_apply_async = _mp_pool.Pool.apply_async
        def apply_async(self, *args, **kwargs):
            _record("pool_async", 1)
            return _old_apply_async(self, *args, **kwargs)
        _mp_pool.Pool.apply_async = apply_async
except Exception:
    pass

try:
    import multiprocessing.process as _mp_process
    _old_start = _mp_process.BaseProcess.start
    def start(self, *args, **kwargs):
        _record("process_start", 1)
        return _old_start(self, *args, **kwargs)
    _mp_process.BaseProcess.start = start
except Exception:
    pass
'''
        with open(os.path.join(hooks_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
            f.write(hook)

        unique_count = 8 + secrets.randbelow(6)
        languages = ["en", "es", "fr", "ja", "ar"]
        prefixes = ["Alpha", "Zulu", "éclair", "こんにちは", "مرحبا"]
        records = []
        for i in range(unique_count):
            day = 10 + (i // 8)
            hour = [2, 9, 15, 21][i % 4]
            records.append({
                "ts": f"2037-04-{day:02d}T{hour:02d}:{(i * 7) % 60:02d}:00Z",
                "id": secrets.token_hex(12),
                "text": f"{prefixes[i % len(prefixes)]}-{secrets.token_hex(8)}",
                "lang": languages[(i * 3) % len(languages)],
            })

        all_rows = records + [dict(records[i]) for i in range(min(4, len(records)))]
        secrets.SystemRandom().shuffle(all_rows)
        file_rows = [[] for _ in range(4)]
        for i, row in enumerate(all_rows):
            file_rows[i % len(file_rows)].append(row)
        for i, rows in enumerate(file_rows):
            with open(os.path.join(input_dir, f"part-{i}.jsonl"), "w", encoding="utf-8") as f:
                for row in rows:
                    f.write(json.dumps(row, ensure_ascii=False) + "\n")

        buckets = {}
        for row in records:
            hour = row["ts"][:13] + ":00:00Z"
            bucket = buckets.setdefault(hour, {"langs": set(), "texts": []})
            bucket["langs"].add(row["lang"])
            bucket["texts"].append(row["text"])
        expected = "\n".join(
            f"Hour: {hour} | Unique Langs: {len(buckets[hour]['langs'])} | Sample: {min(buckets[hour]['texts'])}"
            for hour in sorted(buckets)
        )

        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)
        env = os.environ.copy()
        env["PYTHONPATH"] = hooks_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["ETL_PARALLEL_MARKER"] = marker

        run_etl(input_dir, output_dir, env)
        summary_path = os.path.join(output_dir, "summary.txt")
        assert os.path.isfile(summary_path), "The ETL did not create summary.txt for a supplied output directory."
        with open(summary_path, "r", encoding="utf-8") as f:
            first = f.read().strip()
        assert first == expected, f"Dynamic-input summary was incorrect.\nExpected:\n{expected}\nGot:\n{first}"

        run_etl(input_dir, output_dir, env)
        with open(summary_path, "r", encoding="utf-8") as f:
            second = f.read().strip()
        assert second == first, "Dynamic-input rerun was not idempotent."

        assert os.path.isfile(marker), "No multiprocessing or concurrent.futures operation was observed."
        observed_units = 0
        with open(marker, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    _, amount = line.strip().split(":", 1)
                    observed_units += int(amount)
                except ValueError:
                    pass
        assert observed_units >= 2, "The imported parallel-processing library was not actually used for multiple work items."

        assert os.path.isfile(LOG_PATH), "The dynamic ETL run did not create /home/user/pipeline.log."
        with open(LOG_PATH, "r", encoding="utf-8") as f:
            log_content = f.read()
        assert f"Total unique records: {unique_count}" in log_content, "The log did not report the dynamically derived unique-record count."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
