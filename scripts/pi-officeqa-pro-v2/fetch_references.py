# /// script
# requires-python = ">=3.12"
# dependencies = ["beautifulsoup4==4.14.3"]
# ///
"""Capture 50 complete reference documents without a document-parsing service."""

import concurrent.futures
import csv
import hashlib
import io
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[2] / "datasets/pi-officeqa-pro-v2"
CACHE = ROOT / ".cache"
DOCUMENTS = ROOT / "documents"
PDFS = ROOT / "environment/pdfs"
MANIFEST = ROOT / "sources.json"
for directory in (CACHE, DOCUMENTS, PDFS):
    directory.mkdir(parents=True, exist_ok=True)
previous = {entry["id"]: entry for entry in json.loads(MANIFEST.read_text())} if MANIFEST.exists() else {}

# All 26 series in the publisher's G.5A annual table on the snapshot date.
FX_SERIES = """AEXUSAL AEXBZUS AEXCAUS AEXCHUS AEXDNUS AEXUSEU AEXHKUS AEXINUS
AEXJPUS AEXMAUS AEXMXUS AEXUSNZ AEXNOUS AEXSIUS AEXSFUS AEXKOUS AEXSLUS AEXSDUS
AEXSZUS AEXTAUS AEXTHUS AEXUSUK AEXVZUS TWEXBGSANL TWEXAFEGSANL TWEXEMEGSANL""".split()
GDP_SERIES = ["NOMINALGDP", "REALGDP", "GDPDEFLATION", "POPULATION", "NOMGDPCP", "GDPCP"]
CHAPTERS = {
    "A": "Wealth and Income",
    "B": "Population Characteristics and Migration",
    "C": "Vital Statistics, Health, and Nutrition",
    "D": "Labor Force, Wages, and Working Conditions",
    "E": "Agriculture",
    "F": "Land, Forestry, and Fisheries",
    "G": "Minerals and Power",
    "H": "Construction and Housing",
    "J": "Manufactures",
    "K": "Transportation",
    "L": "Price Indexes",
    "M": "Balance of Payments and Foreign Trade",
    "N": "Banking and Finance",
    "P": "Government",
}


def fetch(url: str, name: str) -> tuple[bytes, dict]:
    path = CACHE / name
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".part")
        subprocess.run(
            [
                "curl",
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--globoff",
                "--retry",
                "2",
                "--max-time",
                "90",
                url,
                "-o",
                str(temporary),
            ],
            check=True,
        )
        temporary.replace(path)
    data = path.read_bytes()
    return data, {"url": url, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}


def capture(spec: tuple[str, str]) -> dict:
    family, key = spec
    identifier = f"{family}__{key.lower()}"
    if identifier in previous:
        entry = previous[identifier]
        document = DOCUMENTS / entry["document"]
        assert hashlib.sha256(document.read_bytes()).hexdigest() == entry["document_sha256"], document
        if "pdf" in entry:
            pdf = PDFS / entry["pdf"]
            if not pdf.exists():
                content, source = fetch(entry["source"]["url"], pdf.name)
                assert source == entry["source"], f"Source changed: {identifier}"
                pdf.write_bytes(content)
            assert hashlib.sha256(pdf.read_bytes()).hexdigest() == entry["source"]["sha256"], pdf
        return entry
    captured = datetime.now(timezone.utc).isoformat()
    if family == "fred":
        content, source = fetch(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={key}", f"{identifier}.csv")
        html, description = fetch(f"https://fred.stlouisfed.org/series/{key}", f"{identifier}.html")
        soup = BeautifulSoup(html, "html.parser")
        title = soup.select_one("#series-title-text-container").get_text(" ", strip=True)
        notes = soup.select_one("#notes").get_text("\n", strip=True)
        body = f"{notes}\n\nData (CSV):\n{content.decode()}"
        rows = list(csv.DictReader(io.StringIO(content.decode())))
        assert rows and set(rows[0]) == {"observation_date", key}, identifier
        details = {
            "observations": len(rows),
            "first_observation": rows[0]["observation_date"],
            "last_observation": rows[-1]["observation_date"],
            "metadata_source": description,
        }
    elif family == "measuringworth":
        dataset = "uscpi" if key == "CPI" else "usgdp"
        first = 1774 if key == "CPI" else 1790
        url = f"https://www.measuringworth.com/datasets/{dataset}/export.php?year_source={first}&year_result=2025"
        if key != "CPI":
            url += f"&use[]={key}"
        content, source = fetch(url, f"{identifier}.csv")
        html, description = fetch(f"https://www.measuringworth.com/datasets/{dataset}/", f"{identifier}.html")
        soup = BeautifulSoup(html, "html.parser")
        rows = list(csv.reader(io.StringIO(content.decode())))
        numeric = [row for row in rows if len(row) == 2 and re.fullmatch(r"\d{4}", row[0])]
        assert len(numeric) == 2026 - first, identifier
        header = next(row for row in rows if len(row) == 2 and row[0] == "Year")
        title = f"MeasuringWorth: {header[1]} ({first}–2025)"
        main = soup.select_one("#content") or soup.select_one("#main")
        assert main is not None, identifier
        for node in main.select("script, style, form"):
            node.decompose()
        body = f"{main.get_text(chr(10), strip=True)}\n\nData (CSV):\n{content.decode()}"
        details = {
            "observations": len(numeric),
            "first_observation": numeric[0][0],
            "last_observation": numeric[-1][0],
            "metadata_source": description,
        }
    else:
        url = f"https://www2.census.gov/library/publications/1949/compendia/hist_stats_1789-1945/hist_stats_1789-1945-ch{key}.pdf"
        content, source = fetch(url, f"{identifier}.pdf")
        assert content.startswith(b"%PDF-"), identifier
        pdf = PDFS / f"{identifier}.pdf"
        pdf.write_bytes(content)
        result = subprocess.run(["pdftotext", "-layout", str(pdf), "-"], check=True, capture_output=True, text=True)
        pages = result.stdout.split("\f")
        if not pages[-1].strip():
            pages.pop()
        assert all(page.strip() for page in pages), identifier
        title = f"Historical Statistics of the United States, 1789–1945 (1949): Chapter {key}. {CHAPTERS[key]}"
        body = f"Original PDF: /workspace/pdfs/{pdf.name}\n\n"
        body += "\n\n".join(f"--- PDF PAGE {number} ---\n{page.rstrip()}" for number, page in enumerate(pages, 1))
        details = {
            "pages": len(pages),
            "pdf": pdf.name,
            "extraction": "Existing PDF text layer, pdftotext -layout; no new OCR.",
        }
    document = DOCUMENTS / f"{identifier}.txt"
    document.write_text(
        f"{title}\nSource: {source['url']}\nCaptured: {captured}\nSHA-256: {source['sha256']}\n\n{body}\n"
    )
    print(f"Captured {identifier}", flush=True)
    return {
        "id": identifier,
        "title": title,
        "document": document.name,
        "captured_at": captured,
        "source": source,
        "document_sha256": hashlib.sha256(document.read_bytes()).hexdigest(),
        "document_bytes": document.stat().st_size,
        **details,
    }


specs = [("fred", series) for series in FX_SERIES + ["PAYEMS", "PPIACO", "RIFSPFFNA"]]
specs += [("measuringworth", series) for series in GDP_SERIES + ["CPI"]]
specs += [("census_1949", chapter) for chapter in CHAPTERS]
assert len(specs) == 50
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    entries = sorted(pool.map(capture, specs), key=lambda entry: entry["id"])
assert len(list(DOCUMENTS.glob("*.txt"))) == 50
MANIFEST.write_text(json.dumps(entries, indent=2) + "\n")
print(f"Captured 50 documents, {sum(entry['document_bytes'] for entry in entries):,} text bytes.")
