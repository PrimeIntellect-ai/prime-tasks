#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import pandas as pd
import pytest
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

EVALUATOR = "/home/user/evaluate_model.py"
TEST_PIPELINE = "/home/user/test_pipeline.py"
DATA = "/home/user/data.csv"
ACCURACY = "/home/user/accuracy.txt"
PASS_LOG = "/home/user/test_pass.log"


def run_python(path, env=None):
    return subprocess.run(
        [sys.executable, path],
        text=True,
        capture_output=True,
        timeout=120,
        env=env,
    )


def read_accuracy():
    with open(ACCURACY, "r") as f:
        raw = f.read()
    assert re.fullmatch(r"[01]\.\d{4}\n?", raw), \
        f"accuracy.txt must contain only a score with exactly four decimal places; got {raw!r}"
    return raw.strip()


def reference_accuracy(frame):
    vectors = CountVectorizer().fit_transform(frame["review"])
    x_train, x_test, y_train, y_test = train_test_split(
        vectors, frame["sentiment"], test_size=0.25, random_state=42
    )
    model = LogisticRegression(random_state=42)
    model.fit(x_train, y_train)
    return f"{accuracy_score(y_test, model.predict(x_test)):.4f}"


def make_challenge_data():
    rows = []
    for i in range(160):
        label = (i * 17 + i // 7) % 2
        signal = "bright excellent pleasant" if label else "dark awful unpleasant"
        # Unique and shared tokens make this a nontrivial text-classification input.
        rows.append({
            "review": f"{signal} shared token{i % 13} item{i}",
            "sentiment": label,
        })
    return pd.DataFrame(rows)


def test_evaluate_model_script_exists():
    path = EVALUATOR
    assert os.path.isfile(path), f"The script {path} is missing."


def test_test_pipeline_script_exists():
    path = TEST_PIPELINE
    assert os.path.isfile(path), f"The script {path} is missing."


def test_accuracy_file_exists_and_content():
    path = ACCURACY
    assert os.path.isfile(path), f"The output file {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "1.0000", f"Expected accuracy.txt to contain '1.0000', but got '{content}'."


def test_test_pass_log_exists():
    path = PASS_LOG
    assert os.path.isfile(path), f"The log file {path} is missing. The reproducibility test may have failed or was not executed."


def test_evaluator_executes_required_pipeline_on_fresh_input():
    original_data = tempfile.NamedTemporaryFile(suffix=".csv", delete=False).name
    shutil.copy2(DATA, original_data)
    challenge = make_challenge_data()
    expected = reference_accuracy(challenge)

    hook_dir = tempfile.mkdtemp(prefix="pipeline_hooks_")
    trace = os.path.join(hook_dir, "trace.jsonl")
    hook = r'''
import json
import os
import pandas as pd
import sklearn.feature_extraction.text as text_mod
import sklearn.linear_model as linear_mod
import sklearn.metrics as metrics_mod
import sklearn.model_selection as selection_mod

TRACE = os.environ["PIPELINE_TRACE"]
def record(name, details=None):
    with open(TRACE, "a") as f:
        f.write(json.dumps({"name": name, "details": details or {}}) + "\\n")

_old_read_csv = pd.read_csv
def read_csv(path, *args, **kwargs):
    record("read_csv", {"path": os.fspath(path)})
    return _old_read_csv(path, *args, **kwargs)
pd.read_csv = read_csv

_old_vectorizer = text_mod.CountVectorizer
def CountVectorizer(*args, **kwargs):
    record("CountVectorizer")
    return _old_vectorizer(*args, **kwargs)
text_mod.CountVectorizer = CountVectorizer

_old_split = selection_mod.train_test_split
def train_test_split(*args, **kwargs):
    record("train_test_split", {
        "test_size": kwargs.get("test_size"),
        "random_state": kwargs.get("random_state")
    })
    return _old_split(*args, **kwargs)
selection_mod.train_test_split = train_test_split

_old_lr = linear_mod.LogisticRegression
def LogisticRegression(*args, **kwargs):
    record("LogisticRegression", {"random_state": kwargs.get("random_state")})
    return _old_lr(*args, **kwargs)
linear_mod.LogisticRegression = LogisticRegression

_old_accuracy = metrics_mod.accuracy_score
def accuracy_score(*args, **kwargs):
    record("accuracy_score")
    return _old_accuracy(*args, **kwargs)
metrics_mod.accuracy_score = accuracy_score
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(hook)

    try:
        challenge.to_csv(DATA, index=False)
        if os.path.exists(ACCURACY):
            os.remove(ACCURACY)
        env = os.environ.copy()
        env["PIPELINE_TRACE"] = trace
        env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
        result = run_python(EVALUATOR, env=env)
        assert result.returncode == 0, result.stdout + result.stderr
        assert os.path.isfile(ACCURACY), "evaluate_model.py did not create accuracy.txt"
        assert read_accuracy() == expected

        assert os.path.isfile(trace), "The required ML operations were not observed"
        with open(trace) as f:
            events = [json.loads(line) for line in f if line.strip()]
        names = [event["name"] for event in events]
        for required in ["read_csv", "CountVectorizer", "train_test_split", "LogisticRegression", "accuracy_score"]:
            assert required in names, f"evaluate_model.py did not use {required}"

        reads = [e for e in events if e["name"] == "read_csv"]
        assert any(e["details"].get("path") == DATA for e in reads), \
            "evaluate_model.py must load /home/user/data.csv with pandas"
        splits = [e for e in events if e["name"] == "train_test_split"]
        assert any(e["details"].get("test_size") == 0.25 and e["details"].get("random_state") == 42 for e in splits), \
            "train_test_split must use test_size=0.25 and random_state=42"
        models = [e for e in events if e["name"] == "LogisticRegression"]
        assert any(e["details"].get("random_state") == 42 for e in models), \
            "LogisticRegression must use random_state=42"
    finally:
        shutil.copy2(original_data, DATA)
        os.unlink(original_data)
        shutil.rmtree(hook_dir, ignore_errors=True)

    # Restore the canonical final output by executing the submitted evaluator.
    result = run_python(EVALUATOR)
    assert result.returncode == 0, result.stdout + result.stderr
    assert read_accuracy() == "1.0000"


def write_negative_wrapper(path, counter):
    code = f'''import os
COUNTER = {counter!r}
ACCURACY = {ACCURACY!r}
def main():
    try:
        with open(COUNTER) as f:
            n = int(f.read())
    except (OSError, ValueError):
        n = 0
    n += 1
    with open(COUNTER, "w") as f:
        f.write(str(n))
    with open(ACCURACY, "w") as f:
        f.write("0.1000" if n % 2 else "0.2000")
if __name__ == "__main__":
    main()
'''
    with open(path, "w") as f:
        f.write(code)


def write_counting_wrapper(path, original, marker):
    code = f'''import importlib.util
import runpy
ORIGINAL = {original!r}
MARKER = {marker!r}
def _mark():
    with open(MARKER, "a") as f:
        f.write("run\\n")
if __name__ == "__main__":
    _mark()
    runpy.run_path(ORIGINAL, run_name="__main__")
else:
    _spec = importlib.util.spec_from_file_location("_submitted_evaluator", ORIGINAL)
    _module = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_module)
    for _name, _value in vars(_module).items():
        if not _name.startswith("__") and _name != "main":
            globals()[_name] = _value
    if hasattr(_module, "main") and callable(_module.main):
        def main(*args, **kwargs):
            _mark()
            return _module.main(*args, **kwargs)
    else:
        _mark()
'''
    with open(path, "w") as f:
        f.write(code)


def test_reproducibility_script_rejects_variation_and_runs_pipeline_five_times():
    backup = tempfile.NamedTemporaryFile(suffix=".py", delete=False).name
    shutil.copy2(EVALUATOR, backup)
    counter = tempfile.NamedTemporaryFile(delete=False).name
    marker = tempfile.NamedTemporaryFile(delete=False).name
    os.unlink(counter)
    os.unlink(marker)

    try:
        # A real reproducibility test must not create the pass log for differing runs.
        write_negative_wrapper(EVALUATOR, counter)
        if os.path.exists(PASS_LOG):
            os.remove(PASS_LOG)
        run_python(TEST_PIPELINE)
        assert not os.path.exists(PASS_LOG), \
            "test_pipeline.py created test_pass.log even though run outputs differed"
        assert os.path.isfile(counter) and open(counter).read().strip() == "5", \
            "test_pipeline.py must execute evaluate_model.py exactly five times"

        # With the real evaluator, it must execute all five runs and create an empty log.
        write_counting_wrapper(EVALUATOR, backup, marker)
        if os.path.exists(PASS_LOG):
            os.remove(PASS_LOG)
        result = run_python(TEST_PIPELINE)
        assert result.returncode == 0, result.stdout + result.stderr
        assert os.path.isfile(marker), "test_pipeline.py did not execute evaluate_model.py"
        with open(marker) as f:
            runs = len(f.readlines())
        assert runs == 5, f"Expected exactly 5 evaluator executions, observed {runs}"
        assert os.path.isfile(PASS_LOG), "A reproducible pipeline did not create test_pass.log"
        assert os.path.getsize(PASS_LOG) == 0, "test_pass.log must be empty"
        assert read_accuracy() == "1.0000"
    finally:
        shutil.copy2(backup, EVALUATOR)
        os.unlink(backup)
        for path in (counter, marker):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
