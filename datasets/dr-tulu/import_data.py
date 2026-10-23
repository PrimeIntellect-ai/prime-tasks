# /// script
# requires-python = ">=3.11"
# dependencies = ["pyarrow==25.0.0"]
# ///
"""Reproduce the pinned public DR Tulu question/rubric import."""

import hashlib
import io
import json
from collections import Counter
from pathlib import Path
from urllib.request import urlopen

import pyarrow.parquet as pq

REPOSITORY = "rl-research/dr-tulu-rl-data"
REVISION = "cb3afa5054d50f856104d939bf6fb939441028e2"
SOURCE_PATH = "data/train-00000-of-00001.parquet"
SOURCE_SHA256 = "da3f8955fa17a11117d353163db7b5f3d672637c2166d3383aefb9ba21413161"
SOURCE_URL = (
    f"https://huggingface.co/datasets/{REPOSITORY}/resolve/{REVISION}/{SOURCE_PATH}"
)
SOURCES = {
    "rl_rag_train_sa_3k_longform_rubrics_adaptive_rubric": "searcharena",
    "rl_rag_train_sqa_1k_clean_search_rubric_longform_rubrics_adaptive_rubric": "sqa",
    "rl_rag_train_os_0915_2k_search_rubric_longform_rubrics_adaptive_rubric": "openscholar",
}


def main() -> None:
    with urlopen(SOURCE_URL, timeout=60) as response:
        source_bytes = response.read()
    if hashlib.sha256(source_bytes).hexdigest() != SOURCE_SHA256:
        raise ValueError("Pinned source parquet checksum mismatch")

    upstream = pq.read_table(io.BytesIO(source_bytes)).to_pylist()
    rows = []
    for index, original in enumerate(upstream):
        messages = original["messages"]
        if len(messages) != 1 or messages[0]["role"] != "user":
            raise ValueError(f"Unexpected conversation shape at upstream row {index}")
        question = messages[0]["content"]
        rubrics = json.loads(original["ground_truth"])["rubrics"]
        rows.append(
            {
                "upstream_index": index,
                "question_id": hashlib.sha256(question.encode("utf-8")).hexdigest(),
                "source": SOURCES[original["source"]],
                "question": question,
                "rubrics": rubrics,
                "split": "train" if rubrics else "excluded",
            }
        )

    eligible = sorted(
        (row for row in rows if row["rubrics"]),
        key=lambda row: (row["question_id"], row["upstream_index"]),
    )
    for row in eligible[:100]:
        row["split"] = "eval"
    train_ids = {row["question_id"] for row in rows if row["split"] == "train"}
    eval_ids = {row["question_id"] for row in rows if row["split"] == "eval"}
    if train_ids & eval_ids:
        raise ValueError("Duplicate questions cross the fixed train/eval boundary")

    output = Path(__file__).resolve().parent
    data = "".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
        for row in rows
    ).encode("utf-8")
    manifest = {
        "schema_version": 1,
        "status": "raw_import_not_quality_certified",
        "upstream": {
            "repository": REPOSITORY,
            "revision": REVISION,
            "split": "train",
            "path": SOURCE_PATH,
            "url": SOURCE_URL,
            "sha256": SOURCE_SHA256,
            "bytes": len(source_bytes),
            "rows": len(upstream),
            "card_url": f"https://huggingface.co/datasets/{REPOSITORY}/blob/{REVISION}/README.md",
            "license": "odc-by",
            "license_url": "https://opendatacommons.org/licenses/by/1-0/",
        },
        "output": {
            "path": "tasks.jsonl",
            "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data),
            "rows": len(rows),
        },
        "source_mapping": SOURCES,
        "source_counts": dict(sorted(Counter(row["source"] for row in rows).items())),
        "split_counts": dict(sorted(Counter(row["split"] for row in rows).items())),
        "source_split_counts": {
            source: dict(
                sorted(
                    Counter(
                        row["split"] for row in rows if row["source"] == source
                    ).items()
                )
            )
            for source in sorted(SOURCES.values())
        },
        "question_id": "sha256 of the exact question encoded as UTF-8; duplicate questions share an ID",
        "row_id": "upstream_index is the unique zero-based position in the pinned upstream train split",
        "split_policy": {
            "eval_size": 100,
            "selection": "First 100 nonempty-rubric rows sorted by (question_id, upstream_index), globally before source filters",
            "empty_rubrics": "Retained with split=excluded; not assigned to train or eval",
            "duplicate_questions": "Preserved; no question_id overlap between train and eval",
        },
        "transformations": [
            "Preserve upstream row order and exact messages[0].content as question",
            "Parse ground_truth JSON and preserve its rubrics list and all rubric fields",
            "Map the three upstream source labels to short aliases",
            "Add upstream_index, question_id and fixed split labels",
            "Omit question_type, dataset and the separate ground_truth.query field",
        ],
    }
    (output / "tasks.jsonl").write_bytes(data)
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Imported {len(rows)} rows: {manifest['split_counts']}")


if __name__ == "__main__":
    main()
