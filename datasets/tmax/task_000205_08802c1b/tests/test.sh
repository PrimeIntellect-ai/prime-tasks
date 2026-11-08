#!/bin/bash
set -e
mkdir -p /logs/verifier

# Replace the public fixtures with fresh inputs so precomputed output files cannot pass.
python3 - <<'PY'
import secrets
from pathlib import Path

base = secrets.randbelow(800000) + 10000
nonce = secrets.token_hex(6)
raw = [
    f"{base + 31}\tScience\tHello {nonce} World! This is a test.",
    "A\tMath\tInvalid ID here",
    f"{base + 7}\tMath\tC++ is extremely fast {nonce}!",
    f"{base + 12}\t\tMissing category string",
    f"{base + 19}\tBi0logy\tInvalid category name",
    f"{base + 3}\tHistory\tIn 1914 several events started.",
    f"{base + 28}\tCS\tCode",
    f"{base + 1}\tArt\tThe Mona Lisa is a half-length portrait {nonce}.",
    f"0\tPhysics\tThis identifier is not positive.",
    f"{base + 45}\tPhysics\tQUANTUM mechanics and theory {nonce}.",
]
queries = [
    f"{base + 1001}\tScience\tHello {nonce} testing World.",
    f"{base + 1002}\tCS\tC++ programming is quick {nonce}.",
    f"{base + 1003}\tPhysics\tQUANTUM theory {nonce} rules!",
    "B\tArt\tInvalid query",
    f"{base + 1004}\tArt\tA half-length portrait of Mona Lisa.",
]
Path('/home/user/raw_data.tsv').write_text('\n'.join(raw) + '\n', encoding='utf-8')
Path('/home/user/queries.tsv').write_text('\n'.join(queries) + '\n', encoding='utf-8')
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import csv
import glob
import shlex
import subprocess

PIPELINE_TRACE = "/tmp/pipeline.trace"
COMPILER_LOG = "/tmp/verifier-gpp.log"


def _trace_has_compile_command(trace):
    for line in trace.splitlines():
        line = line.lstrip("+ ")
        try:
            tokens = shlex.split(line)
        except ValueError:
            continue
        if not tokens:
            continue
        if tokens[0] == "command" and len(tokens) > 1:
            tokens = tokens[1:]
        if os.path.basename(tokens[0]) == "g++" and "-std=c++17" in tokens and "-O3" in tokens:
            return True
    return False


def setup_module(module):
    for path in [
        "/home/user/invalid_rows.log",
        "/home/user/valid_embeddings.csv",
        "/home/user/retrieval_results.csv",
        COMPILER_LOG,
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    os.makedirs("/tmp/verifier-bin", exist_ok=True)
    wrapper = "/tmp/verifier-bin/g++"
    with open(wrapper, "w") as f:
        f.write("#!/bin/bash\n")
        f.write("printf '%q ' \"$@\" >> /tmp/verifier-gpp.log\n")
        f.write("printf '\\n' >> /tmp/verifier-gpp.log\n")
        f.write("exec /usr/bin/g++ \"$@\"\n")
    os.chmod(wrapper, 0o755)

    env = os.environ.copy()
    env["PATH"] = "/tmp/verifier-bin:" + env.get("PATH", "")
    result = subprocess.run(
        ["bash", "-x", "/home/user/run_pipeline.sh"],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    with open(PIPELINE_TRACE, "w") as f:
        f.write(result.stderr)
    assert result.returncode == 0, (
        "run_pipeline.sh failed with exit code %d\nstdout:\n%s\nstderr:\n%s"
        % (result.returncode, result.stdout, result.stderr)
    )

    compiler_invoked = False
    if os.path.exists(COMPILER_LOG):
        with open(COMPILER_LOG) as f:
            for line in f:
                try:
                    args = shlex.split(line)
                except ValueError:
                    continue
                if "-std=c++17" in args and "-O3" in args:
                    compiler_invoked = True
                    break
    assert compiler_invoked or _trace_has_compile_command(result.stderr), (
        "run_pipeline.sh did not invoke g++ with -std=c++17 and -O3"
    )


def is_valid_row(row):
    if len(row) != 3:
        return False
    id_str, category, text = row

    # 1. ID is strictly positive integer
    if not id_str.isdigit() or int(id_str) <= 0:
        return False

    # 2. Category is non-empty, only alphabetic
    if not category or not category.isalpha():
        return False

    # 3. Text is non-empty, at least 5 chars
    if not text or len(text) < 5:
        return False

    return True


def compute_features(text):
    length = len(text)
    vowels = sum(1 for c in text if c in "AEIOUaeiou")
    consonants = sum(1 for c in text if c.isalpha() and c not in "AEIOUaeiou")
    uppercase = sum(1 for c in text if c.isupper())
    spaces = sum(1 for c in text if c == ' ')

    vec = [length, vowels, consonants, uppercase, spaces]
    norm = math.sqrt(sum(x*x for x in vec))
    if norm == 0:
        return None
    return [x / norm for x in vec]


def process_file(filepath):
    valid_rows = []
    invalid_line_numbers = []

    with open(filepath, 'r', encoding='utf-8') as f:
        for i, line in enumerate(f):
            row = line.rstrip('\n').split('\t')
            if is_valid_row(row):
                vec = compute_features(row[2])
                if vec is not None:
                    valid_rows.append((int(row[0]), vec))
                else:
                    invalid_line_numbers.append(i + 1)
            else:
                invalid_line_numbers.append(i + 1)

    return valid_rows, invalid_line_numbers


def cosine_similarity(v1, v2):
    return sum(x*y for x, y in zip(v1, v2))


def test_pipeline_files_exist():
    assert os.path.exists("/home/user/run_pipeline.sh"), "run_pipeline.sh is missing"
    assert os.access("/home/user/run_pipeline.sh", os.X_OK), "run_pipeline.sh is not executable"
    assert glob.glob("/home/user/*.cpp"), "C++ source file is missing"
    assert os.path.exists("/home/user/invalid_rows.log"), "invalid_rows.log is missing"
    assert os.path.exists("/home/user/valid_embeddings.csv"), "valid_embeddings.csv is missing"
    assert os.path.exists("/home/user/retrieval_results.csv"), "retrieval_results.csv is missing"


def test_invalid_rows_log():
    raw_valid, raw_invalid = process_file("/home/user/raw_data.tsv")
    query_valid, query_invalid = process_file("/home/user/queries.tsv")

    # The prompt says "If a row is invalid, its 1-based line number should be appended to /home/user/invalid_rows.log"
    # We will check if the invalid lines from raw_data.tsv are in the log.
    # It's possible the agent appended queries' invalid lines too, or restarted the log.
    # We will just check that the invalid lines from raw_data.tsv appear in order.

    with open("/home/user/invalid_rows.log", "r") as f:
        logged_lines = [int(line.strip()) for line in f if line.strip().isdigit()]

    # At minimum, the raw_data.tsv invalid lines should be there.
    for line_num in raw_invalid:
        assert line_num in logged_lines, f"Line {line_num} from raw_data.tsv should be logged as invalid."


def test_valid_embeddings():
    raw_valid, _ = process_file("/home/user/raw_data.tsv")

    expected_embeddings = {row[0]: row[1] for row in raw_valid}

    actual_embeddings = {}
    with open("/home/user/valid_embeddings.csv", "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            id_val = int(row[0])
            vec = [float(x) for x in row[1:6]]
            actual_embeddings[id_val] = vec

    assert len(actual_embeddings) == len(expected_embeddings), "Mismatch in number of valid embeddings."

    for id_val, expected_vec in expected_embeddings.items():
        assert id_val in actual_embeddings, f"Missing embedding for ID {id_val}"
        actual_vec = actual_embeddings[id_val]
        for act, exp in zip(actual_vec, expected_vec):
            assert math.isclose(act, exp, abs_tol=1e-3), f"Embedding mismatch for ID {id_val}: expected {expected_vec}, got {actual_vec}"


def test_retrieval_results():
    raw_valid, _ = process_file("/home/user/raw_data.tsv")
    query_valid, _ = process_file("/home/user/queries.tsv")

    expected_results = {}
    for q_id, q_vec in query_valid:
        best_score = -1.0
        best_id = -1
        for r_id, r_vec in raw_valid:
            score = cosine_similarity(q_vec, r_vec)
            if score > best_score + 1e-7:
                best_score = score
                best_id = r_id
            elif abs(score - best_score) <= 1e-7:
                if r_id < best_id:
                    best_id = r_id
        expected_results[q_id] = (best_id, best_score)

    actual_results = {}
    with open("/home/user/retrieval_results.csv", "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            q_id = int(row[0])
            m_id = int(row[1])
            score = float(row[2])
            actual_results[q_id] = (m_id, score)

    for q_id, (exp_m_id, exp_score) in expected_results.items():
        assert q_id in actual_results, f"Missing retrieval result for Query ID {q_id}"
        act_m_id, act_score = actual_results[q_id]
        assert act_m_id == exp_m_id, f"Wrong matched ID for Query {q_id}: expected {exp_m_id}, got {act_m_id}"
        assert math.isclose(act_score, exp_score, abs_tol=1e-3), f"Wrong score for Query {q_id}: expected {exp_score}, got {act_score}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
