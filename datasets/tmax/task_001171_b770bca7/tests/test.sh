#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess


def generate_random_triple():
    subject = "".join(random.choices(string.ascii_uppercase, k=3))
    predicate = "".join(random.choices(string.ascii_lowercase, k=random.randint(4, 6)))
    obj = "".join(random.choices(string.ascii_uppercase, k=3))
    return subject, predicate, obj


def compare_with_oracle(agent_path, pred1, pred2, stdin_data, label):
    oracle_proc = subprocess.run(
        ["/app/kg_matcher", pred1, pred2],
        input=stdin_data,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert oracle_proc.returncode == 0, (
        f"Oracle failed on {label}:\n{stdin_data}\n"
        f"Args: {pred1} {pred2}\nStderr: {oracle_proc.stderr}"
    )

    agent_proc = subprocess.run(
        ["python3", agent_path, pred1, pred2],
        input=stdin_data,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert agent_proc.returncode == 0, (
        f"Agent failed on {label}:\n{stdin_data}\n"
        f"Args: {pred1} {pred2}\nStderr: {agent_proc.stderr}"
    )
    assert agent_proc.stdout == oracle_proc.stdout, (
        f"Mismatch on {label}!\nArgs: {pred1} {pred2}\n"
        f"Stdin:\n{stdin_data}\n"
        f"Oracle output:\n{repr(oracle_proc.stdout)}\n"
        f"Agent output:\n{repr(agent_proc.stdout)}"
    )


def test_kg_matcher_fuzz_equivalence():
    oracle_path = "/app/kg_matcher"
    agent_path = "/home/user/kg_matcher.py"

    assert os.path.isfile(agent_path), f"Agent script {agent_path} not found."

    random.seed(42)

    for i in range(100):
        num_lines = random.randint(20, 100)
        triples = [generate_random_triple() for _ in range(num_lines)]
        stdin_data = "\n".join([f"{s}|{p}|{o}" for s, p, o in triples]) + "\n"

        all_preds = list(set([p for s, p, o in triples]))
        if len(all_preds) >= 2 and random.random() < 0.8:
            pred1 = random.choice(all_preds)
            pred2 = random.choice(all_preds)
        else:
            pred1 = "".join(random.choices(string.ascii_lowercase, k=5))
            pred2 = "".join(random.choices(string.ascii_lowercase, k=5))

        oracle_proc = subprocess.run(
            [oracle_path, pred1, pred2],
            input=stdin_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input:\n{stdin_data}\nArgs: {pred1} {pred2}\nStderr: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            ["python3", agent_path, pred1, pred2],
            input=stdin_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent failed on input:\n{stdin_data}\nArgs: {pred1} {pred2}\nStderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout

        assert agent_out == oracle_out, (
            f"Mismatch on test {i}!\n"
            f"Args: {pred1} {pred2}\n"
            f"Stdin:\n{stdin_data}\n"
            f"Oracle output:\n{repr(oracle_out)}\n"
            f"Agent output:\n{repr(agent_out)}"
        )


def test_kg_matcher_join_heavy_fuzz_equivalence():
    agent_path = "/home/user/kg_matcher.py"
    assert os.path.isfile(agent_path), f"Agent script {agent_path} not found."

    rng = random.Random(918273)
    alphabet = string.ascii_letters + string.digits

    def token(prefix):
        return prefix + "_" + "".join(rng.choices(alphabet, k=8))

    for case in range(100):
        pred1 = token("first")
        pred2 = pred1 if case % 11 == 0 else token("second")
        lines = []

        # Plant several many-to-many joins. Duplicated edges verify that result
        # multiplicity is retained rather than deduplicated.
        for bridge_index in range(rng.randint(2, 5)):
            bridge = token(f"bridge{bridge_index}")
            first_edges = []
            second_edges = []
            for _ in range(rng.randint(2, 4)):
                first_edges.append((token("start"), pred1, bridge))
            for _ in range(rng.randint(2, 4)):
                second_edges.append((bridge, pred2, token("target")))
            lines.extend(first_edges)
            lines.extend(second_edges)
            if bridge_index == 0:
                lines.append(first_edges[0])
                lines.append(second_edges[0])

        # Add selected-predicate edges that do not join and unrelated noise.
        for _ in range(rng.randint(8, 20)):
            lines.append((token("deadstart"), pred1, token("deadend")))
            lines.append((token("noiseS"), token("noiseP"), token("noiseO")))
        lines.append((token("orphan"), pred2, token("orphanTarget")))

        rng.shuffle(lines)
        rendered = []
        for index, (subject, predicate, obj) in enumerate(lines):
            if index % 4 == 0:
                rendered.append(f"  {subject} | {predicate} | {obj}  ")
            elif index % 4 == 1:
                rendered.append(f"\t{subject}|{predicate}|{obj}\t")
            else:
                rendered.append(f"{subject}|{predicate}|{obj}")

        # Exercise ignored blank and malformed records without changing the
        # oracle-derived expected output.
        rendered.extend(["", "   ", "missing separators", "only|one"])
        stdin_data = "\n".join(rendered) + "\n"

        oracle_preview = subprocess.run(
            ["/app/kg_matcher", pred1, pred2],
            input=stdin_data,
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert oracle_preview.returncode == 0
        assert oracle_preview.stdout != "[]\n", f"Structured case {case} unexpectedly had no joins"

        compare_with_oracle(
            agent_path, pred1, pred2, stdin_data, f"join-heavy structured test {case}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
