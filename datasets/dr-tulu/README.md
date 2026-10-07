# DR Tulu questions and rubrics

[`tasks.jsonl`](tasks.jsonl) contains all **4,881 public source rows** from
[DR Tulu RL Data](https://huggingface.co/datasets/rl-research/dr-tulu-rl-data)
at revision `cb3afa5054d50f856104d939bf6fb939441028e2`. Questions and rubric
fields are preserved without rewriting. This is a **raw import, not a
quality-certified task collection**: inclusion does not establish that a question
is self-contained, its rubrics are correct, or its evidence is available.

The corpus contains 2,937 SearchArena, 1,000 ScholarQA (`sqa`), and 944 OpenScholar
rows. The 36 OpenScholar rows with empty rubrics remain in the data, marked
`excluded`. It contains no model trajectories or RaR data.

## Schema and identity

Each line is one JSON object in upstream row order:

| Field | Meaning |
| --- | --- |
| `upstream_index` | Unique zero-based row position in the pinned upstream train split. |
| `question_id` | SHA-256 of the exact UTF-8 question, without whitespace normalization. Duplicate questions share this ID. |
| `source` | `searcharena`, `sqa`, or `openscholar`; original labels are mapped in the manifest. |
| `question` | Exact upstream `messages[0].content`. |
| `rubrics` | Parsed upstream `ground_truth.rubrics`, retaining every field and its value. |
| `split` | Fixed `train`, `eval`, or `excluded` assignment. |

The source has no task-ID column. Use `upstream_index` to identify a specific row
and `question_id` to group identical questions. Seven question groups occur twice
among the nonempty-rubric rows; these rows are retained.

## Splits

The 4,845 rows with rubrics are ranked globally by `(question_id, upstream_index)`.
The first 100 are `eval`; the remaining 4,745 are `train`. The 36 rows without
rubrics are `excluded`. These are derived splits; upstream publishes only `train`.

Select sources **after** applying these assignments. The eval set contains 58
SearchArena, 17 ScholarQA, and 25 OpenScholar rows. No identical question appears
in both train and eval. The importer checks this explicitly. Fixed membership
lets a source-specific run retain the same evaluation boundary as an all-source run.

The question/rubric dataset is evaluator-side data. A taskset presents `question`
to the solver and keeps `rubrics` for scoring; do not place this JSONL in a solver
workspace or image. A standard JSON dataset loader can read the file from a URL
pinned to a `prime-tasks` commit. These QA rows need no Harbor task wrappers.

## Reproduce the import

From the repository root:

```sh
uv run datasets/dr-tulu/import_data.py
```

The script downloads only the public source parquet at the pinned revision,
verifies its SHA-256, and deterministically regenerates `tasks.jsonl` and
`manifest.json`. Its PyArrow dependency is declared inline. The manifest records
source and output checksums, source aliases, row counts, and split construction.
It does not silently update to a newer source revision.

## Attribution and license

The source is **DR Tulu RL Data**, published by the DR Tulu authors under
`rl-research`; see [the paper](https://arxiv.org/abs/2511.19399) and the
[pinned dataset card](https://huggingface.co/datasets/rl-research/dr-tulu-rl-data/blob/cb3afa5054d50f856104d939bf6fb939441028e2/README.md).
The card credits prompts from OpenScholar and SearchArena and rubrics generated
with GPT-4.1. The retained source labels additionally identify ScholarQA rows.

This database contains information from DR Tulu RL Data, made available under
the [Open Data Commons Attribution License (ODC-BY) 1.0](https://opendatacommons.org/licenses/by/1-0/).
The imported data retains that license; the repository's MIT license does not
replace it. See [NOTICE](NOTICE). The source card describes intended research
and educational use and refers to
[Ai2's Responsible Use Guidelines](https://allenai.org/responsible-use).
