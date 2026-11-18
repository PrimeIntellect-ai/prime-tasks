#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/sitecustomize.py
import json
import os

try:
    import matplotlib.figure

    _original_savefig = matplotlib.figure.Figure.savefig

    def _audited_savefig(fig, fname, *args, **kwargs):
        result = _original_savefig(fig, fname, *args, **kwargs)
        try:
            if os.path.basename(os.fspath(fname)) == "growth_dynamics.png":
                expected_ids = json.loads(os.environ.get("VERIFIER_SEQUENCE_IDS", "[]"))
                visible_labels = []
                trajectory_count = 0

                for ax in fig.axes:
                    legend = ax.get_legend()
                    if legend is not None:
                        visible_labels.extend(t.get_text() for t in legend.get_texts())
                    visible_labels.extend(t.get_text() for t in ax.texts)

                    for line in ax.lines:
                        try:
                            x = list(line.get_xdata())
                            y = list(line.get_ydata())
                            if len(x) >= 2 and len(y) >= 2 and len(set(map(float, y))) >= 2:
                                trajectory_count += 1
                        except Exception:
                            pass

                audit = {
                    "trajectory_count": trajectory_count,
                    "visible_labels": visible_labels,
                    "expected_ids": expected_ids,
                }
                with open("/tmp/plot_audit.json", "w") as f:
                    json.dump(audit, f)
        except Exception as exc:
            with open("/tmp/plot_audit.json", "w") as f:
                json.dump({"error": repr(exc)}, f)
        return result

    matplotlib.figure.Figure.savefig = _audited_savefig
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess
import uuid

import matplotlib.image as mpimg
import numpy as np

NOTEBOOK = "/home/user/workflow.ipynb"
FASTA = "/home/user/sequences.fasta"
PLOT = "/home/user/growth_dynamics.png"
RESULTS = "/home/user/final_populations.json"

sequences = {}


def _make_sequence(gc_count, length):
    chars = (["G", "C"] * ((gc_count + 1) // 2))[:gc_count]
    chars += (["A", "T"] * (((length - gc_count) + 1) // 2))[:length - gc_count]
    random.SystemRandom().shuffle(chars)
    return "".join(chars)


def test_workflow_notebook_exists():
    assert os.path.isfile(NOTEBOOK), "The notebook /home/user/workflow.ipynb was not found."


def test_notebook_executes_start_to_finish():
    global sequences
    specs = [(4, 37), (19, 41), (34, 43), (43, 47)]
    sequences = {
        "verify_" + uuid.uuid4().hex[:12]: _make_sequence(gc, length)
        for gc, length in specs
    }

    with open(FASTA, "w") as f:
        for seq_id, seq in sequences.items():
            f.write(f">{seq_id}\n{seq}\n")

    for path in (PLOT, RESULTS, "/tmp/plot_audit.json"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["VERIFIER_SEQUENCE_IDS"] = json.dumps(list(sequences))
    completed = subprocess.run(
        [
            "jupyter", "nbconvert", "--to", "notebook", "--execute", "--inplace",
            "--ExecutePreprocessor.timeout=120", NOTEBOOK,
        ],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, "Notebook execution failed:\n" + completed.stdout[-4000:]

    with open(NOTEBOOK) as f:
        notebook = json.load(f)
    assert isinstance(notebook, dict) and isinstance(notebook.get("cells"), list), "workflow.ipynb is not a valid notebook."
    code_cells = [c for c in notebook["cells"] if c.get("cell_type") == "code" and "".join(c.get("source", [])).strip()]
    assert code_cells, "The notebook contains no executable code."
    assert all(c.get("execution_count") is not None for c in code_cells), "Not all notebook code cells were executed."


def test_plot_exists():
    assert os.path.isfile(PLOT), "The plot /home/user/growth_dynamics.png was not found."
    assert os.path.getsize(PLOT) > 5000, "The plot file is empty or implausibly small."
    with open(PLOT, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "growth_dynamics.png is not a PNG file."

    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] >= 300 and image.shape[1] >= 300, "The plot has invalid or unusably small dimensions."
    assert float(np.std(image)) > 0.01, "The plot image appears blank."

    assert os.path.isfile("/tmp/plot_audit.json"), "The executed notebook did not save the requested matplotlib plot."
    with open("/tmp/plot_audit.json") as f:
        audit = json.load(f)
    assert "error" not in audit, f"Could not inspect the generated plot: {audit.get('error')}"
    assert audit.get("trajectory_count", 0) >= len(sequences), "The plot does not contain a trajectory for every strain."
    visible = "\n".join(map(str, audit.get("visible_labels", [])))
    for seq_id in sequences:
        assert seq_id in visible, f"The generated plot does not visibly label strain '{seq_id}'."


def test_final_populations():
    json_path = RESULTS
    assert os.path.isfile(json_path), f"The output file {json_path} was not found."

    class NumberToken(float):
        def __new__(cls, raw):
            obj = float.__new__(cls, raw)
            obj.raw = raw
            return obj

    with open(json_path, "r") as f:
        try:
            results = json.load(
                f,
                parse_float=NumberToken,
                parse_int=NumberToken,
                parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)),
            )
        except (json.JSONDecodeError, ValueError):
            assert False, f"{json_path} is not a valid finite-number JSON file."

    assert isinstance(results, dict), f"{json_path} must contain a JSON object."

    fasta_path = FASTA
    assert os.path.isfile(fasta_path), "The input file sequences.fasta is missing."

    parsed_sequences = {}
    current_seq = ""
    with open(fasta_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                current_seq = line[1:]
                parsed_sequences[current_seq] = ""
            elif current_seq:
                parsed_sequences[current_seq] += line

    K = 1000
    P0 = 10
    t = 10

    for seq_id, seq in parsed_sequences.items():
        assert seq_id in results, f"Missing strain '{seq_id}' in {json_path}"
        actual_p = results[seq_id]
        assert isinstance(actual_p, NumberToken) and not isinstance(actual_p, bool), f"Population for {seq_id} must be a JSON number."
        assert re.fullmatch(r"-?(?:0|[1-9][0-9]*)\.[0-9]", actual_p.raw), f"Population for {seq_id} must be written with exactly one decimal place."

        gc_count = seq.count("G") + seq.count("C")
        r = gc_count / len(seq) if len(seq) > 0 else 0
        expected_p = K / (1 + ((K - P0) / P0) * math.exp(-r * t))
        expected_rounded = round(expected_p, 1)
        assert abs(float(actual_p) - expected_rounded) <= 1.0, f"Population for {seq_id} is {actual_p.raw}, expected approximately {expected_rounded:.1f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
