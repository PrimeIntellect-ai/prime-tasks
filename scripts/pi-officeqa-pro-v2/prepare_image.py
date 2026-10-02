# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Verify and package the pinned OfficeQA corpus and its 50 reference additions."""

import argparse
import hashlib
import json
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "datasets/pi-officeqa-pro-v2"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--documents", type=Path, required=True, help="Pinned upstream parsed_corpus/jsons directory.")
parser.add_argument("--pdfs", type=Path, required=True, help="Pinned upstream PDFs directory.")
args = parser.parse_args()
upstream = json.loads((ROOT / "upstream.json").read_text())
sources = json.loads((ROOT / "sources.json").read_text())
files = []
for entry in upstream["files"]:
    directory = args.documents if entry["path"].startswith("documents/") else args.pdfs
    path = directory / Path(entry["path"]).name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], path
    files.append((path, entry["path"]))
assert len(list(args.documents.glob("*.json"))) == 1435
assert len(sources) == len(list((ROOT / "documents").glob("*.txt"))) == 50
for entry in sources:
    path = ROOT / "documents" / entry["document"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == entry["document_sha256"], path
    files.append((path, f"documents/{path.name}"))
    if "pdf" in entry:
        pdf = ROOT / "environment/pdfs" / entry["pdf"]
        assert hashlib.sha256(pdf.read_bytes()).hexdigest() == entry["source"]["sha256"], pdf
        files.append((pdf, f"pdfs/{pdf.name}"))
files.append((ROOT / "sources.json", "reference-sources.json"))
archive_path = ROOT / "environment/corpus.tar.gz"
with tarfile.open(archive_path, "w:gz", compresslevel=6, dereference=True) as archive:
    for path, name in sorted(files, key=lambda item: item[1]):
        info = archive.gettarinfo(path, arcname=name)
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mtime = 0
        info.mode = 0o644
        with path.open("rb") as handle:
            archive.addfile(info, handle)
print(
    json.dumps(
        {
            "archive": str(archive_path),
            "documents": 1485,
            "pdfs": 44,
            "archive_bytes": archive_path.stat().st_size,
            "uncompressed_bytes": sum(path.stat().st_size for path, _ in files),
            "sha256": hashlib.sha256(archive_path.read_bytes()).hexdigest(),
        },
        indent=2,
    )
)
