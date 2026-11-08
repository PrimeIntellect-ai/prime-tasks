#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
import sys
from collections import Counter, defaultdict

PAPERS_FILE = "/home/user/papers.jsonl"
OUTPUT_FILE = "/home/user/influential_topics.json"
SCRIPT_FILE = "/home/user/analyze_graph.py"


def compute_expected(papers):
    by_id = {paper["id"]: paper for paper in papers}
    cited_by = defaultdict(set)
    for paper_id, paper in by_id.items():
        for ref in paper.get("references", []):
            cited_by[ref].add(paper_id)

    expected = {}
    for paper_id in by_id:
        citing_papers = cited_by[paper_id]
        if len(citing_papers) >= 3 and all(
            len(cited_by[citing_id]) >= 1 for citing_id in citing_papers
        ):
            topics = Counter()
            for citing_id in citing_papers:
                for topic in by_id[citing_id].get("topics", []):
                    topics[topic] += 1
            ordered = sorted(topics.items(), key=lambda item: (-item[1], item[0]))
            expected[paper_id] = [topic for topic, _ in ordered[:2]]
    return expected


def read_papers():
    papers = []
    with open(PAPERS_FILE, "r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                papers.append(json.loads(line))
    return papers


def read_and_check_output(expected):
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."
    with open(OUTPUT_FILE, "r", encoding="utf-8") as handle:
        try:
            student_output = json.load(handle)
        except json.JSONDecodeError:
            assert False, f"{OUTPUT_FILE} does not contain valid JSON."

    assert isinstance(student_output, dict), (
        f"Output JSON must be an object (dict), got {type(student_output).__name__}."
    )
    assert student_output == expected, (
        "Output does not match expected results.\n"
        f"Expected: {expected}\nGot: {student_output}"
    )


def execute_script():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    result = subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_FILE} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def random_name(prefix):
    return f"{prefix}_{secrets.token_hex(8)}"


def build_unseen_fixture():
    papers = []

    influential_a = random_name("paper")
    influential_b = random_name("paper")
    non_influential = random_name("paper")

    topics_a = [random_name("topic") for _ in range(3)]
    topics_b = [random_name("topic") for _ in range(4)]

    papers.append({"id": influential_a, "authors": ["A"], "references": [], "topics": []})
    a_citers = [random_name("paper") for _ in range(3)]
    a_topic_lists = [
        [topics_a[0], topics_a[1]],
        [topics_a[0], topics_a[2]],
        [topics_a[1], topics_a[2]],
    ]
    for paper_id, topic_list in zip(a_citers, a_topic_lists):
        papers.append({
            "id": paper_id,
            "authors": [random_name("author")],
            "references": [influential_a],
            "topics": topic_list,
        })
    papers.append({
        "id": random_name("paper"),
        "authors": ["downstream"],
        "references": a_citers,
        "topics": [random_name("irrelevant")],
    })

    papers.append({"id": influential_b, "authors": ["B"], "references": [], "topics": []})
    b_citers = [random_name("paper") for _ in range(4)]
    b_topic_lists = [
        [topics_b[0], topics_b[1]],
        [topics_b[0], topics_b[2]],
        [topics_b[0], topics_b[1]],
        [topics_b[3]],
    ]
    for paper_id, topic_list in zip(b_citers, b_topic_lists):
        papers.append({
            "id": paper_id,
            "authors": [random_name("author")],
            "references": [influential_b],
            "topics": topic_list,
        })
        papers.append({
            "id": random_name("paper"),
            "authors": ["downstream"],
            "references": [paper_id],
            "topics": [],
        })

    papers.append({"id": non_influential, "authors": ["C"], "references": [], "topics": []})
    decoy_citers = [random_name("paper") for _ in range(3)]
    for paper_id in decoy_citers:
        papers.append({
            "id": paper_id,
            "authors": ["decoy"],
            "references": [non_influential],
            "topics": [random_name("decoy_topic")],
        })
    # Only two of the three citing papers are themselves cited, so this candidate fails.
    papers.append({
        "id": random_name("paper"),
        "authors": ["decoy_downstream"],
        "references": decoy_citers[:2],
        "topics": [],
    })

    random.SystemRandom().shuffle(papers)
    return papers


def test_final_state():
    assert os.path.exists(PAPERS_FILE), f"Input file {PAPERS_FILE} is missing."
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."
    assert os.path.exists(SCRIPT_FILE), f"Required script {SCRIPT_FILE} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT_FILE).st_mode), (
        f"{SCRIPT_FILE} must be a regular Python source file."
    )

    with open(PAPERS_FILE, "rb") as handle:
        original_papers = handle.read()
    with open(OUTPUT_FILE, "rb") as handle:
        original_output = handle.read()

    try:
        # Recompute the original fixture's truth, execute the submitted script, and
        # retain the original exact output assertion.
        expected_original = compute_expected(read_papers())
        execute_script()
        read_and_check_output(expected_original)

        # Exercise the script on an unpredictable fixture so a fixed JSON answer
        # cannot pass in place of the requested implementation.
        unseen_papers = build_unseen_fixture()
        with open(PAPERS_FILE, "w", encoding="utf-8") as handle:
            for paper in unseen_papers:
                handle.write(json.dumps(paper) + "\n")
        expected_unseen = compute_expected(unseen_papers)
        execute_script()
        read_and_check_output(expected_unseen)
    finally:
        with open(PAPERS_FILE, "wb") as handle:
            handle.write(original_papers)
        with open(OUTPUT_FILE, "wb") as handle:
            handle.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
