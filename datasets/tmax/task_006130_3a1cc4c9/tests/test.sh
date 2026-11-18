#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_script_exists_and_executable():
    script_path = "/home/user/process_data.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_manifest_csv():
    manifest_path = "/home/user/manifest.csv"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "docA,2023,tech,4",
        "docB,2023,sci,6",
        "docC,2022,tech,4"
    ]

    assert lines == expected_lines, f"Manifest contents are incorrect. Expected {expected_lines}, got {lines}"


def test_processed_tokens_docA():
    tok_path = "/home/user/processed/2023/tech/docA.tok"
    assert os.path.isfile(tok_path), f"Token file {tok_path} does not exist."

    with open(tok_path, "r") as f:
        tokens = [line.strip() for line in f if line.strip()]

    expected_tokens = ["hello", "world", "test", "2023"]
    assert tokens == expected_tokens, f"Tokens for docA are incorrect. Expected {expected_tokens}, got {tokens}"


def test_processed_tokens_docB():
    tok_path = "/home/user/processed/2023/sci/docB.tok"
    assert os.path.isfile(tok_path), f"Token file {tok_path} does not exist."

    with open(tok_path, "r") as f:
        tokens = [line.strip() for line in f if line.strip()]

    expected_tokens = ["data", "science", "fun", "data", "data", "data"]
    assert tokens == expected_tokens, f"Tokens for docB are incorrect. Expected {expected_tokens}, got {tokens}"


def test_processed_tokens_docC():
    tok_path = "/home/user/processed/2022/tech/docC.tok"
    assert os.path.isfile(tok_path), f"Token file {tok_path} does not exist."

    with open(tok_path, "r") as f:
        tokens = [line.strip() for line in f if line.strip()]

    expected_tokens = ["stopwords", "should", "removed", "right"]
    assert tokens == expected_tokens, f"Tokens for docC are incorrect. Expected {expected_tokens}, got {tokens}"


def test_docD_not_processed():
    tok_path = "/home/user/processed/2022/sci/docD.tok"
    assert not os.path.exists(tok_path), f"Token file {tok_path} should not exist since docD.txt was missing."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_behavior.py
import os
import re
import shutil
import subprocess
import uuid
from pathlib import Path

home = Path("/home/user")
data = home / "data"
docs = data / "docs"
processed = home / "processed"
manifest = home / "manifest.csv"
script = home / "process_data.sh"

suffix = uuid.uuid4().hex[:12]
doc_z = "zeta" + suffix
doc_a = "alpha" + suffix
doc_m = "middle" + suffix
missing = "missing" + suffix
year_z = "31" + suffix[:4]
year_a = "27" + suffix[4:8]
year_m = "29" + suffix[8:12]
cat_z = "tech" + suffix[:5]
cat_a = "science" + suffix[5:10]
cat_m = "mixed" + suffix[2:7]
nonce = "nonce" + suffix

stopwords = {"the", "beta", "stopx", "a"}
documents = {
    doc_z: f"Alpha,BETA\tkeep42---STOPX\ncan't café Z9 {nonce.upper()}!\n",
    doc_a: "THE the Thematic\n123! MIX_ed\n",
    doc_m: "Tabs\there and\nmultiple   spaces; A aa.\n",
}
records = [
    (doc_z, year_z, cat_z),
    (missing, "2099", "absent" + suffix[:4]),
    (doc_m, year_m, cat_m),
    (doc_a, year_a, cat_a),
]


def expected_tokens(text):
    cleaned = re.sub(r"[^a-z0-9\s]", " ", text.lower())
    return [token for token in cleaned.split() if token not in stopwords]


shutil.rmtree(docs, ignore_errors=True)
shutil.rmtree(processed, ignore_errors=True)
docs.mkdir(parents=True)
processed.mkdir(parents=True)
if manifest.exists() or manifest.is_symlink():
    manifest.unlink()

data.mkdir(parents=True, exist_ok=True)
(data / "stopwords.txt").write_text("\n".join(sorted(stopwords)) + "\n", encoding="utf-8")
(data / "metadata.tsv").write_text(
    "\n".join("\t".join(record) for record in records) + "\n",
    encoding="utf-8",
)
for doc_id, text in documents.items():
    (docs / f"{doc_id}.txt").write_text(text, encoding="utf-8")

result = subprocess.run(
    [str(script)],
    cwd=str(home),
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=30,
)
assert result.returncode == 0, (
    f"process_data.sh failed with exit code {result.returncode}. "
    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
)

expected_manifest = []
expected_paths = set()
for doc_id, year, category in records:
    if doc_id not in documents:
        continue
    tokens = expected_tokens(documents[doc_id])
    tok_path = processed / year / category / f"{doc_id}.tok"
    assert tok_path.is_file(), f"Expected token file {tok_path} was not created"
    actual_lines = tok_path.read_text(encoding="utf-8").splitlines()
    assert actual_lines == tokens, (
        f"Incorrect tokens for dynamic document {doc_id}: expected {tokens}, got {actual_lines}"
    )
    expected_paths.add(tok_path.resolve())
    expected_manifest.append(f"{doc_id},{year},{category},{len(tokens)}")

missing_path = processed / "2099" / ("absent" + suffix[:4]) / f"{missing}.tok"
assert not missing_path.exists(), "A metadata entry with no source document was processed"

assert manifest.is_file(), "The script did not generate /home/user/manifest.csv"
actual_manifest = manifest.read_text(encoding="utf-8").splitlines()
expected_manifest.sort(key=lambda line: line.split(",", 1)[0])
assert actual_manifest == expected_manifest, (
    f"Dynamic manifest is incorrect: expected {expected_manifest}, got {actual_manifest}"
)

actual_paths = {path.resolve() for path in processed.rglob("*.tok") if path.is_file()}
assert actual_paths == expected_paths, (
    f"Unexpected or missing token files: expected {sorted(map(str, expected_paths))}, "
    f"got {sorted(map(str, actual_paths))}"
)
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_dynamic_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
