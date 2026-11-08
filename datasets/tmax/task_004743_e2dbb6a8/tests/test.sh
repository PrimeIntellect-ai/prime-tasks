#!/bin/bash
set -u
mkdir -p /logs/verifier

TEST_FILE="/tmp/test_final_state_$$.py"
cat > "$TEST_FILE" <<'TEST_EOF'
import os
import re
from collections import Counter

FIXTURES = {
    "doc1.txt": "Data analysis is critical. Data data data! Science is also science.\n",
    "doc2.txt": "The machine learning model needs more data. Algorithms and algorithms.\n",
    "doc3.txt": "Data science involves linear algebra. Algebra is fundamental to algorithms.\n",
    "doc4.txt": "Nothing to see here, just some random text without much meaning.\n",
    "doc5.txt": "Science data algorithms algebra algebra algebra!\n",
}


def test_final_state():
    script_path = "/home/user/organize.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} is missing."
    assert not os.path.islink(script_path), f"{script_path} must be a regular script, not a symlink."

    high_dir = "/home/user/high_relevance"
    low_dir = "/home/user/low_relevance"

    assert os.path.isdir(high_dir), f"Directory {high_dir} is missing. The task requires creating it."
    assert os.path.isdir(low_dir), f"Directory {low_dir} is missing. The task requires creating it."

    # Collect all text files from the output directories to rebuild the corpus.
    files = {}
    occurrences = []
    for d in [high_dir, low_dir]:
        for fname in os.listdir(d):
            if fname.endswith(".txt"):
                occurrences.append(fname)
                assert fname not in files, f"File {fname} appears in both output directories."
                with open(os.path.join(d, fname), "r") as f:
                    files[fname] = f.read()

    assert len(files) == 5, f"Expected exactly 5 .txt files across high/low relevance directories, but found {len(files)}. Did you move all files?"
    assert sorted(occurrences) == sorted(FIXTURES), (
        f"Output filenames do not match the supplied dataset fixtures. "
        f"Expected {sorted(FIXTURES)}, got {sorted(occurrences)}."
    )
    assert files == FIXTURES, "The moved files' contents do not match the supplied dataset fixtures."

    datasets_dir = "/home/user/datasets"
    assert os.path.isdir(datasets_dir), f"Dataset directory {datasets_dir} is missing."
    remaining = [name for name in os.listdir(datasets_dir) if name.endswith(".txt")]
    assert remaining == [], f"Dataset files were not moved; still present: {sorted(remaining)}"

    # Process text: punctuation to spaces, lowercase.
    def extract_words(text):
        text = re.sub(r'[^\w\s]', ' ', text).lower()
        return [w for w in text.split() if len(w) > 2 and w.isalnum() and not w.isdigit()]

    all_words = []
    for content in files.values():
        all_words.extend(extract_words(content))

    counts = Counter(all_words)
    sorted_words = sorted(counts.items(), key=lambda x: (-x[1], x[0]))
    top_5 = sorted_words[:5]
    weights = {top_5[i][0]: 5 - i for i in range(len(top_5))}

    expected_scores = {}
    for fname, content in files.items():
        f_words = extract_words(content)
        f_counts = Counter(f_words)
        score = sum(f_counts[w] * weights.get(w, 0) for w in weights)
        expected_scores[fname] = score

    # Verify file locations based on recomputed scores.
    for fname, score in expected_scores.items():
        if score >= 15:
            expected_path = os.path.join(high_dir, fname)
            assert os.path.exists(expected_path), f"File {fname} has a score of {score} (>= 15) and should be in {high_dir}."
        else:
            expected_path = os.path.join(low_dir, fname)
            assert os.path.exists(expected_path), f"File {fname} has a score of {score} (< 15) and should be in {low_dir}."

    # Verify the log file.
    log_path = "/home/user/scores.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, "r") as f:
        log_lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected_log = [f"{fname}:{score}" for fname, score in sorted(expected_scores.items())]
    assert log_lines == expected_log, (
        f"Log file {log_path} contents do not match expected output.\n"
        f"Expected: {expected_log}\nGot: {log_lines}"
    )
TEST_EOF

reset_fixtures() {
    rm -rf /home/user/datasets /home/user/high_relevance /home/user/low_relevance
    rm -f /home/user/scores.log
    mkdir -p /home/user/datasets
    cat > /home/user/datasets/doc1.txt <<'EOF'
Data analysis is critical. Data data data! Science is also science.
EOF
    cat > /home/user/datasets/doc2.txt <<'EOF'
The machine learning model needs more data. Algorithms and algorithms.
EOF
    cat > /home/user/datasets/doc3.txt <<'EOF'
Data science involves linear algebra. Algebra is fundamental to algorithms.
EOF
    cat > /home/user/datasets/doc4.txt <<'EOF'
Nothing to see here, just some random text without much meaning.
EOF
    cat > /home/user/datasets/doc5.txt <<'EOF'
Science data algorithms algebra algebra algebra!
EOF
    chown -R user:user /home/user/datasets
    chmod -R 777 /home/user/datasets
}

passed=1

# Check the state left by the agent against the actual supplied fixtures.
if ! python3 -m pytest "$TEST_FILE" -x --tb=short 2>&1; then
    passed=0
fi

# Restore the original input and execute the submitted artifact to verify that it
# itself performs the required processing, rather than merely leaving a forged state.
if [ "$passed" -eq 1 ]; then
    reset_fixtures
    if ! timeout 30s runuser -u user -- bash /home/user/organize.sh; then
        passed=0
    elif ! python3 -m pytest "$TEST_FILE" -x --tb=short 2>&1; then
        passed=0
    fi
fi

rm -f "$TEST_FILE"
if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
