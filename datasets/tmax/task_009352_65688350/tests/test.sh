#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import pytest

def get_embedding(text):
    text = text.strip()
    length = len(text) / 100.0
    words = len(text.split()) / 20.0
    vowels = sum(1 for c in text.lower() if c in "aeiou") / 50.0
    consonants = sum(1 for c in text.lower() if c in "bcdfghjklmnpqrstvwxyz") / 50.0
    ascii_sum = sum(ord(c) for c in text) % 10 / 10.0
    return [round(length, 3), round(words, 3), round(vowels, 3), round(consonants, 3), round(ascii_sum, 3)]

def cosine_similarity(v1, v2):
    dot = sum(x * y for x, y in zip(v1, v2))
    mag1 = math.sqrt(sum(x * x for x in v1))
    mag2 = math.sqrt(sum(x * x for x in v2))
    if mag1 == 0 or mag2 == 0:
        return 0.0
    return dot / (mag1 * mag2)

def test_index_tsv():
    index_path = "/home/user/index.tsv"
    assert os.path.isfile(index_path), f"{index_path} does not exist."

    with open(index_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected 5 lines in {index_path}, got {len(lines)}."

    dataset_dir = "/home/user/datasets"
    expected_files = sorted(os.listdir(dataset_dir))

    for i, expected_file in enumerate(expected_files):
        parts = lines[i].split("\t")
        assert len(parts) == 2, f"Line {i+1} in {index_path} is not tab-separated correctly."
        filename, vector_str = parts
        assert filename == expected_file, f"Expected filename {expected_file} at line {i+1}, got {filename}. Check sorting."

        with open(os.path.join(dataset_dir, expected_file), "r") as df:
            content = df.read()

        expected_vec = get_embedding(content)
        expected_vec_str = ",".join(str(v) for v in expected_vec)

        assert vector_str == expected_vec_str, f"Expected vector {expected_vec_str} for {filename}, got {vector_str}."

def test_recommendations():
    rec_path = "/home/user/recommendations.txt"
    assert os.path.isfile(rec_path), f"{rec_path} does not exist."

    with open(rec_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {rec_path}, got {len(lines)}."

    query = "Genomic and RNA sequencing"
    query_vec = get_embedding(query)

    dataset_dir = "/home/user/datasets"
    similarities = []
    for ds in os.listdir(dataset_dir):
        if not ds.endswith(".txt"): continue
        with open(os.path.join(dataset_dir, ds), "r") as df:
            content = df.read()
        ds_vec = get_embedding(content)
        sim = cosine_similarity(query_vec, ds_vec)
        similarities.append((sim, ds))

    similarities.sort(key=lambda x: x[0], reverse=True)
    expected_top1 = similarities[0][1]
    expected_top2 = similarities[1][1]

    assert lines[0] == expected_top1, f"Expected top recommendation to be {expected_top1}, got {lines[0]}."
    assert lines[1] == expected_top2, f"Expected second recommendation to be {expected_top2}, got {lines[1]}."

def test_test_result():
    res_path = "/home/user/test_result.txt"
    assert os.path.isfile(res_path), f"{res_path} does not exist."

    with open(res_path, "r") as f:
        content = f.read().strip()

    assert content == "PASS", f"Expected 'PASS' in {res_path}, got '{content}'."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_pipeline_behavior.py
import math
import os
import shutil
import subprocess
import uuid

HOME = "/home/user"
DATASETS = os.path.join(HOME, "datasets")
BUILD = os.path.join(HOME, "build_index.sh")
RECOMMEND = os.path.join(HOME, "recommend.sh")
REPRO = os.path.join(HOME, "test_reproducibility.sh")

def embedding(text):
    text = text.strip()
    return [
        round(len(text) / 100.0, 3),
        round(len(text.split()) / 20.0, 3),
        round(sum(1 for c in text.lower() if c in "aeiou") / 50.0, 3),
        round(sum(1 for c in text.lower() if c in "bcdfghjklmnpqrstvwxyz") / 50.0, 3),
        round(sum(ord(c) for c in text) % 10 / 10.0, 3),
    ]

def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    ma = math.sqrt(sum(x * x for x in a))
    mb = math.sqrt(sum(x * x for x in b))
    return 0.0 if ma == 0 or mb == 0 else dot / (ma * mb)

def expected_rows(contents):
    return [name + "\t" + ",".join(str(v) for v in embedding(contents[name])) for name in sorted(contents)]

def assert_exact_index(path, contents):
    assert os.path.isfile(path), f"{path} was not created"
    with open(path) as f:
        rows = [line.rstrip("\n") for line in f if line.strip()]
    assert rows == expected_rows(contents), f"Unexpected index contents in {path}: {rows}"

def parse_index(path):
    result = []
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            name, vector = line.rstrip("\n").split("\t")
            result.append((name, [float(x) for x in vector.split(",")]))
    return result

def run_repro_mode(mode, hidden_build, counter, mutator):
    for path in (counter, os.path.join(HOME, "index_run1.tsv"), os.path.join(HOME, "index_run2.tsv"), os.path.join(HOME, "test_result.txt")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    wrapper = f'''#!/bin/bash
set -e
n=0
if [ -f {counter!r} ]; then n=$(cat {counter!r}); fi
n=$((n+1))
printf '%s' "$n" > {counter!r}
bash {hidden_build!r} "$@"
if [ "$n" -eq 2 ] && [ {mode!r} != normal ]; then
    python3 {mutator!r} {mode!r}
fi
'''
    with open(BUILD, "w") as f:
        f.write(wrapper)
    os.chmod(BUILD, 0o755)
    proc = subprocess.run(["bash", REPRO], cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert os.path.isfile(counter) and open(counter).read().strip() == "2", "test_reproducibility.sh must invoke build_index.sh exactly twice"
    assert os.path.isfile(os.path.join(HOME, "test_result.txt")), "test_reproducibility.sh did not create test_result.txt"
    return proc, open(os.path.join(HOME, "test_result.txt")).read().strip()

scripts = (BUILD, RECOMMEND, REPRO)
for script in scripts:
    assert os.path.isfile(script), f"Required Bash script missing: {script}"
    assert os.path.getsize(script) > 0, f"Required Bash script is empty: {script}"
    syntax = subprocess.run(["bash", "-n", script], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, f"Invalid Bash syntax in {script}: {syntax.stderr}"

tag = uuid.uuid4().hex
backup = os.path.join(HOME, ".datasets_verifier_backup_" + tag)
hidden_build = os.path.join(HOME, ".build_index_verifier_original_" + tag + ".sh")
counter = "/tmp/build_counter_" + tag
mutator = "/tmp/mutate_index_" + tag + ".py"
contents = {
    "alpha_ocean.txt": "Marine coral reef photographs and salinity observations " + tag,
    "bravo_genes.txt": "Genome variants and messenger RNA expression in rare disease samples " + tag,
    "charlie_finance.txt": "Quarterly bond prices, interest rates, and company earnings " + tag,
    "delta_climate.txt": "Daily rainfall, wind speed, and mountain temperature stations " + tag,
    "echo_language.txt": "Annotated multilingual speech recordings and phoneme labels " + tag,
}

os.replace(DATASETS, backup)
os.mkdir(DATASETS)
os.replace(BUILD, hidden_build)
try:
    for name, text in contents.items():
        with open(os.path.join(DATASETS, name), "w") as f:
            f.write(text)
    with open(os.path.join(DATASETS, "ignore.csv"), "w") as f:
        f.write("This non-txt file must not be indexed")

    subprocess.run(["bash", hidden_build], cwd=HOME, check=True)
    assert_exact_index(os.path.join(HOME, "index.tsv"), contents)

    no_arg = subprocess.run(["bash", RECOMMEND], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    two_args = subprocess.run(["bash", RECOMMEND, "one", "two"], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert no_arg.returncode != 0, "recommend.sh must reject zero arguments"
    assert two_args.returncode != 0, "recommend.sh must reject more than one argument"

    query = None
    ranked = None
    for i in range(100):
        candidate = "RNA genome query " + tag + " marker" + str(i)
        scores = sorted(((cosine(embedding(candidate), embedding(text)), name) for name, text in contents.items()), reverse=True)
        if abs(scores[0][0] - scores[1][0]) > 1e-12 and abs(scores[1][0] - scores[2][0]) > 1e-12:
            query, ranked = candidate, scores
            break
    assert query is not None, "Could not construct a non-tied verifier query"
    subprocess.run(["bash", RECOMMEND, query], cwd=HOME, check=True)
    with open(os.path.join(HOME, "recommendations.txt")) as f:
        recommendations = [line.strip() for line in f if line.strip()]
    assert recommendations == [ranked[0][1], ranked[1][1]], f"recommend.sh returned {recommendations} for a fresh query"

    with open(mutator, "w") as f:
        f.write('''import sys
path = "/home/user/index.tsv"
with open(path) as h:
    lines = h.readlines()
name, vec = lines[0].rstrip("\\n").split("\\t")
values = vec.split(",")
if sys.argv[1] == "equivalent":
    values[0] = values[0] + "0"
elif sys.argv[1] == "mismatch":
    values[0] = str(float(values[0]) + 0.125)
lines[0] = name + "\\t" + ",".join(values) + "\\n"
with open(path, "w") as h:
    h.writelines(lines)
''')

    proc, result = run_repro_mode("equivalent", hidden_build, counter, mutator)
    assert result == "PASS", f"Numerically identical vectors with different formatting must PASS; got {result}"
    run1 = os.path.join(HOME, "index_run1.tsv")
    run2 = os.path.join(HOME, "index_run2.tsv")
    assert os.path.isfile(run1) and os.path.isfile(run2), "Both reproducibility index files must be saved"
    assert open(run1, "rb").read() != open(run2, "rb").read(), "Verifier formatting mutation did not take effect"
    parsed1, parsed2 = parse_index(run1), parse_index(run2)
    assert parsed1 == parsed2, "Equivalent-mode vectors were not numerically equal"

    proc, result = run_repro_mode("mismatch", hidden_build, counter, mutator)
    assert result == "FAIL", f"A nonzero L2 difference must produce FAIL; got {result}"

    proc, result = run_repro_mode("normal", hidden_build, counter, mutator)
    assert proc.returncode == 0 and result == "PASS", f"Reproducibility test did not PASS on deterministic builds: {proc.stderr}"
    assert_exact_index(os.path.join(HOME, "index_run1.tsv"), contents)
    assert_exact_index(os.path.join(HOME, "index_run2.tsv"), contents)
finally:
    try:
        os.remove(BUILD)
    except FileNotFoundError:
        pass
    if os.path.exists(hidden_build):
        os.replace(hidden_build, BUILD)
    if os.path.exists(DATASETS):
        shutil.rmtree(DATASETS)
    if os.path.exists(backup):
        os.replace(backup, DATASETS)
    for path in (counter, mutator):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
TEST_EOF

ok=1
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_pipeline_behavior.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
