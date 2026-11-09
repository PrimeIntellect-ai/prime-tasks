#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import subprocess
import tempfile
import time
from pathlib import Path


def validate_metrics(path, processed, accepted, elapsed_ms, require_positive=False):
    assert os.path.exists(path), f"Metrics JSON not created: {path}"
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert data.get("processed_count") == processed, "Incorrect processed_count in metrics"
    assert data.get("accepted_count") == accepted, "Incorrect accepted_count in metrics"
    assert "duration_ms" in data, "duration_ms missing in metrics"

    duration = data["duration_ms"]
    assert isinstance(duration, (int, float)) and not isinstance(duration, bool), "duration_ms must be numeric"
    assert math.isfinite(duration), "duration_ms must be finite"
    assert duration >= 0, "duration_ms must be non-negative"
    if require_positive:
        assert duration > 0, "duration_ms must be positive for a nontrivial corpus"
    assert duration <= elapsed_ms + 2000, "duration_ms is not plausible for the observed execution time"


def run_pipeline(go_file, pipeline_dir, corpus, out_dir, metrics, marker):
    env = os.environ.copy()
    env["VERIFIER_STRICT_POLICY_MARKER"] = marker
    start = time.monotonic()
    result = subprocess.run(
        ["go", "run", go_file, "--corpus", corpus, "--out", out_dir, "--metrics", metrics],
        cwd=pipeline_dir,
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    elapsed_ms = (time.monotonic() - start) * 1000
    assert result.returncode == 0, f"Go program failed:\n{result.stderr}"
    assert os.path.exists(marker), "The pipeline did not call StrictPolicy from /app/vendored/bluemonday"
    return elapsed_ms


def instrument_strict_policy():
    root = Path("/app/vendored/bluemonday")
    declaration = re.compile(r"func\s+StrictPolicy\s*\(\s*\)\s*\*Policy\s*\{")
    target = None
    for candidate in root.rglob("*.go"):
        if candidate.name == "verifier_strict_policy_hook.go":
            continue
        text = candidate.read_text(encoding="utf-8")
        if declaration.search(text):
            target = candidate
            break
    assert target is not None, "Could not locate bluemonday.StrictPolicy"

    helper = root / "verifier_strict_policy_hook.go"
    helper.write_text(
        '''package bluemonday

import "os"

func verifierStrictPolicyCalled() {
    if path := os.Getenv("VERIFIER_STRICT_POLICY_MARKER"); path != "" {
        _ = os.WriteFile(path, []byte("called"), 0600)
    }
}
''',
        encoding="utf-8",
    )

    text = target.read_text(encoding="utf-8")
    text, count = declaration.subn(lambda m: m.group(0) + "\n\tverifierStrictPolicyCalled()", text, count=1)
    assert count == 1
    target.write_text(text, encoding="utf-8")


def validate_embedding_source(go_file, pipeline_dir):
    paths = {Path(go_file)}
    paths.update(Path(pipeline_dir).glob("*.go"))
    source = "\n".join(p.read_text(encoding="utf-8") for p in paths if p.exists())
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)

    has_dimension_five = bool(
        re.search(r"\[\s*5\s*\]\s*(?:u?int(?:8|16|32|64)?|float(?:32|64))", source)
        or re.search(r"make\s*\(\s*\[\]\s*(?:u?int(?:8|16|32|64)?|float(?:32|64))\s*,\s*5\s*\)", source)
        or re.search(r"\[\]\s*(?:u?int(?:8|16|32|64)?|float(?:32|64))\s*\{(?:[^{}]*,){4}[^{}]*\}", source)
    )
    assert has_dimension_five, "No 5-dimensional numeric embedding vector was found"

    has_vowels = bool(
        re.search(r'["`]aeiou["`]', source, flags=re.I)
        or all(re.search(r"'" + vowel + r"'", source, flags=re.I) for vowel in "aeiou")
    )
    assert has_vowels, "Embedding code does not identify all five vowels"

    case_insensitive = bool(
        re.search(r"(?:strings|unicode)\.ToLower", source)
        or re.search(r"strings\.EqualFold", source)
        or all(re.search(r"'" + vowel + r"'", source) for vowel in "AEIOU")
    )
    assert case_insensitive, "Embedding vowel counting is not case-insensitive"

    updates_counts = bool(
        re.search(r"\[[^\]]+\]\s*(?:\+\+|\+=|=\s*[^\n]+\+\s*1)", source)
        or re.search(r"(?:strings|bytes)\.Count", source)
    )
    assert updates_counts, "Embedding code does not count vowel occurrences"


def test_final_state():
    go_mod_path = "/app/vendored/bluemonday/go.mod"
    assert os.path.exists(go_mod_path), f"Vendored go.mod not found at {go_mod_path}"
    with open(go_mod_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "module github.com/microcosm-cc/bluemondayy" not in content, "The go.mod file still has the perturbed module name 'bluemondayy'"
    assert "module github.com/microcosm-cc/bluemonday" in content, "The go.mod file should have the correct module name 'bluemonday'"

    pipeline_dir = "/home/user/pipeline"
    go_file = os.path.join(pipeline_dir, "prepare_data.go")
    if not os.path.exists(go_file) and os.path.exists("/home/user/prepare_data.go"):
        go_file = "/home/user/prepare_data.go"
        pipeline_dir = "/home/user"
    assert os.path.exists(go_file), f"Go program not found at {go_file}"

    validate_embedding_source(go_file, pipeline_dir)
    instrument_strict_policy()

    clean_corpus = "/home/user/corpora/clean"
    evil_corpus = "/home/user/corpora/evil"

    with tempfile.TemporaryDirectory() as temp_root:
        clean_out = os.path.join(temp_root, "clean_out")
        evil_out = os.path.join(temp_root, "evil_out")
        os.mkdir(clean_out)
        os.mkdir(evil_out)
        clean_metrics = os.path.join(temp_root, "clean_metrics.json")
        evil_metrics = os.path.join(temp_root, "evil_metrics.json")

        clean_marker = os.path.join(temp_root, "clean_strict.marker")
        elapsed = run_pipeline(go_file, pipeline_dir, clean_corpus, clean_out, clean_metrics, clean_marker)
        expected_clean_names = set(os.listdir(clean_corpus))
        actual_clean_names = set(os.listdir(clean_out))
        missing_clean = expected_clean_names - actual_clean_names
        assert not missing_clean, f"{len(missing_clean)} of {len(expected_clean_names)} clean files modified/rejected: {', '.join(missing_clean)}"
        assert actual_clean_names == expected_clean_names, "Unexpected files were written for the clean corpus"
        for name in expected_clean_names:
            assert Path(clean_out, name).read_bytes() == Path(clean_corpus, name).read_bytes(), f"Clean output content differs for {name}"
        validate_metrics(clean_metrics, len(expected_clean_names), len(expected_clean_names), elapsed)

        evil_marker = os.path.join(temp_root, "evil_strict.marker")
        elapsed = run_pipeline(go_file, pipeline_dir, evil_corpus, evil_out, evil_metrics, evil_marker)
        expected_evil_names = set(os.listdir(evil_corpus))
        actual_evil_names = set(os.listdir(evil_out))
        bypassed_evil = actual_evil_names.intersection(expected_evil_names)
        assert not bypassed_evil, f"{len(bypassed_evil)} of {len(expected_evil_names)} evil files bypassed: {', '.join(bypassed_evil)}"
        assert len(actual_evil_names) == 0, "Evil output directory should be empty"
        validate_metrics(evil_metrics, len(expected_evil_names), 0, elapsed)

        dynamic_corpus = os.path.join(temp_root, "corpus_" + secrets.token_hex(8))
        dynamic_out = os.path.join(temp_root, "out_" + secrets.token_hex(8))
        os.mkdir(dynamic_corpus)
        os.mkdir(dynamic_out)

        token = secrets.token_hex(16)
        accepted = {
            f"plain_{secrets.token_hex(4)}.txt": f"Plain training material {token} with AEIOU and aeiou.",
            f"tags_{secrets.token_hex(4)}.txt": f"<div><b>Rich {token}</b><i> AEIOU text</i></div>",
            f"script_{secrets.token_hex(4)}.txt": f"<script>REJECT_SPAM alert('{token}')</script><p>Visible safe text {token}</p>",
            f"bytes_{secrets.token_hex(4)}.txt": "ééééé",
            f"lower_{secrets.token_hex(4)}.txt": f"This lowercase reject_spam text remains acceptable {token}.",
        }
        expected_outputs = {
            list(accepted)[0]: accepted[list(accepted)[0]],
            list(accepted)[1]: f"Rich {token} AEIOU text",
            list(accepted)[2]: f"Visible safe text {token}",
            list(accepted)[3]: "ééééé",
            list(accepted)[4]: accepted[list(accepted)[4]],
        }

        rejected = {
            f"short_{secrets.token_hex(4)}.txt": "<h1>123456789</h1>",
            f"spam_{secrets.token_hex(4)}.txt": f"Long prefix {token} <b>REJECT_</b>SPAM long suffix",
            f"onlyscript_{secrets.token_hex(4)}.txt": f"<script>long malicious payload {token}</script>",
        }

        for name, text in {**accepted, **rejected}.items():
            Path(dynamic_corpus, name).write_text(text, encoding="utf-8")

        # Make processing substantial enough that a millisecond duration must be positive.
        for i in range(64):
            name = f"bulk_{i}_{secrets.token_hex(3)}.txt"
            text = f"Bulk AEIOU {token} " + ("ordinary vowel-rich training data aeiou " * 1600)
            Path(dynamic_corpus, name).write_text(text, encoding="utf-8")
            expected_outputs[name] = text

        dynamic_metrics = os.path.join(temp_root, "dynamic_metrics.json")
        dynamic_marker = os.path.join(temp_root, "dynamic_strict.marker")
        elapsed = run_pipeline(go_file, pipeline_dir, dynamic_corpus, dynamic_out, dynamic_metrics, dynamic_marker)

        assert set(os.listdir(dynamic_out)) == set(expected_outputs), "Dynamic corpus accepted/rejected filenames are incorrect"
        for name, expected in expected_outputs.items():
            actual = Path(dynamic_out, name).read_text(encoding="utf-8")
            assert actual == expected, f"Sanitized content is incorrect for {name}"

        validate_metrics(
            dynamic_metrics,
            len(accepted) + len(rejected) + 64,
            len(expected_outputs),
            elapsed,
            require_positive=True,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
