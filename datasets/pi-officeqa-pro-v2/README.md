# PI-OfficeQA Pro V2 tasks and offline corpus

## Tasks

[`tasks.json`](tasks.json) contains the final **78 tasks** loaded by `prime-envs`.
It is derived from Databricks' `officeqa_pro_v2.csv` at Hugging Face revision
`65a2b315780417bc50d7bfe6e5bdb904e63fda65`. The 15 prompt repairs and four revised
answers are stored directly in the rows; the 12 excluded tasks are absent. See
[`AUDIT.md`](AUDIT.md) for the evidence and restoration criteria.

Rows preserve the upstream `uid`, original row position as `idx`, `source_docs`,
and `source_files`. Only `question` is shown to the solver; `answer` is used by the
evaluator. The question dataset is downloaded on the evaluator and is never
included in the corpus archive or sandbox image. These tasks retain the upstream
[CC-BY-SA 4.0 license](LICENSE-CC-BY-SA) and attribution in [NOTICE](NOTICE).

## Corpus

This corpus adds exactly **50 reference documents** to the 1,435 upstream documents:
**1,485 searchable documents total**, a 3.48% increase. Every task receives the same corpus.

Prime image: `prime/primeintellect/pi-officeqa-pro-v2:65a2b3157804-offline50-20261002`
(private team visibility). `prime-envs` selects this image for `pi_officeqa_pro_v2` and
disables external solver network access after trusted setup.

| Collection | Documents | Selection |
| --- | ---: | --- |
| FRED foreign exchange | 26 | Every series in the G.5A annual table on October 2, 2026, including its three dollar indexes. |
| FRED economic indicators | 3 | PAYEMS, PPIACO, and RIFSPFFNA, with their complete available histories. |
| MeasuringWorth | 7 | All six U.S. GDP dataset measures plus the annual U.S. CPI series, through 2025. |
| Census | 14 | Every subject chapter of the 1949 Historical Statistics of the United States, 1789–1945. |

The added text occupies 5,449,405 bytes. Series documents contain source definitions,
units, frequency, citations, and complete CSV data. Census documents preserve all 319
pages of the existing text layer, extracted with `pdftotext -layout`. No external
document-parsing service is used. The inherited Census OCR contains transcription
errors, so its 14 source PDFs are included for inspection.

The image also includes the 30 upstream PDFs comprising the complete transition
annual-report family and modern receipts-section family. They provide visual
representations of existing corpus documents, including chart colors and shading.
There are **44 companion PDFs**, occupying 82,963,706 bytes in total; they do not add
44 further source documents. Agents can render pages with the installed Poppler tools.

`sources.json` records reference URLs, capture times, original-byte hashes, and text
hashes. `upstream.json` records the pinned upstream JSON and PDF hashes at Hugging Face
revision `65a2b315780417bc50d7bfe6e5bdb904e63fda65`. These manifests contain no benchmark
questions, answers, task IDs, or mappings from questions to documents.

## Prepare the image

From the repository root, with `uv`, `curl`, and Poppler installed:

```sh
uv run scripts/pi-officeqa-pro-v2/fetch_references.py
uv run scripts/pi-officeqa-pro-v2/prepare_image.py \
  --documents /path/to/pinned/parsed_corpus/jsons \
  --pdfs /path/to/pinned/pdfs
```

The reference fetcher verifies the committed text snapshot and downloads missing Census
PDFs, checking their pinned hashes. It reuses the captured series rather than replacing
them with live revisions. Download the upstream files on the evaluator
using authorized Hugging Face access. The preparer validates every source hash and
packages only corpus documents, companion PDFs, and reference provenance.

The build context is `datasets/pi-officeqa-pro-v2/environment`. Its Dockerfile installs
Poppler, Tesseract, and locked numerical/image libraries for use without internet access.
The generated archive, downloaded PDFs, and HTTP cache are excluded from Git.

Source data retains the terms and attribution of its original publishers. The source
URLs and citations remain inside the reference documents.
