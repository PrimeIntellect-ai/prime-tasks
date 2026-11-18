#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_report_json():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), "report.json was not generated."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON.")

    expected_keys = {"skipped_members", "extracted_files", "generated_md_files"}
    assert set(report.keys()) == expected_keys, f"report.json keys mismatch. Expected {expected_keys}, got {set(report.keys())}"

    assert report["skipped_members"] == 3, f"Expected 3 skipped_members, got {report['skipped_members']}"
    assert report["extracted_files"] == 3, f"Expected 3 extracted_files, got {report['extracted_files']}"
    assert report["generated_md_files"] == 3, f"Expected 3 generated_md_files, got {report['generated_md_files']}"

def test_markdown_files():
    md_dir = "/home/user/docs_md"
    assert os.path.exists(md_dir), "docs_md directory does not exist."
    assert os.path.isdir(md_dir), "docs_md is not a directory."

    expected_files = {
        "API_Reference.md": "# API Reference\n\nThis is the API reference documentation.\n",
        "User_Guide.md": "# User Guide\n\nWelcome to the user guide.\n",
        "Release_Notes.md": "# Release Notes\n\nVersion 2.0 released.\n"
    }

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(md_dir, filename)
        assert os.path.exists(filepath), f"Expected markdown file {filename} is missing."

        with open(filepath, "r") as f:
            content = f.read()

        assert content.strip() == expected_content.strip(), f"Content mismatch in {filename}.\nExpected:\n{expected_content}\nGot:\n{content}"

def test_raw_docs_extraction():
    raw_dir = "/home/user/docs_raw"
    assert os.path.exists(raw_dir), "docs_raw directory does not exist."
    assert os.path.isdir(raw_dir), "docs_raw is not a directory."

    expected_files = {"valid_json.json", "valid_csv.csv", "valid_xml.xml"}
    extracted_files = set(os.listdir(raw_dir))

    assert expected_files.issubset(extracted_files), f"Expected files {expected_files} missing from docs_raw. Found: {extracted_files}"

    malicious_names = {"evil_relative.txt", "evil_absolute.txt", "evil_trick.txt", "evil.txt"}
    for mal in malicious_names:
        assert mal not in extracted_files, f"Malicious file {mal} was extracted to docs_raw!"

def test_no_tar_slip():
    paths_to_check = [
        "/home/user/evil_relative.txt",
        "/home/user/evil_absolute.txt",
        "/home/user/evil_trick.txt",
        "/home/evil_relative.txt",
        "/home/evil_absolute.txt",
        "/home/evil_trick.txt"
    ]

    for path in paths_to_check:
        assert not os.path.exists(path), f"Tar slip vulnerability detected! Malicious file extracted to {path}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_execution.py
import ast
import csv
import io
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import tarfile
from pathlib import Path

script = Path('/home/user/build_docs.py')
assert script.exists(), 'build_docs.py does not exist.'
assert stat.S_ISREG(script.lstat().st_mode), 'build_docs.py must be a regular file.'
source = script.read_text(encoding='utf-8')
assert source.strip(), 'build_docs.py is empty.'
ast.parse(source, filename=str(script))

# Reject the ordinary ways of delegating extraction to a CLI. Extraction must be
# implemented by the submitted Python program itself.
tree = ast.parse(source, filename=str(script))
os_aliases = {'os'}
subprocess_aliases = {'subprocess'}
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            if alias.name == 'os':
                os_aliases.add(alias.asname or alias.name)
            if alias.name == 'subprocess':
                subprocess_aliases.add(alias.asname or alias.name)
    elif isinstance(node, ast.ImportFrom) and node.module == 'os':
        for alias in node.names:
            if alias.name in {'system', 'popen'}:
                raise AssertionError('build_docs.py must not invoke extraction through a CLI.')
    elif isinstance(node, ast.ImportFrom) and node.module == 'subprocess':
        raise AssertionError('build_docs.py must not invoke extraction through a CLI.')

for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
        if node.func.value.id in subprocess_aliases:
            raise AssertionError('build_docs.py must not invoke extraction through a CLI.')
        if node.func.value.id in os_aliases and node.func.attr in {'system', 'popen'}:
            raise AssertionError('build_docs.py must not invoke extraction through a CLI.')

token = secrets.token_hex(10)
titles = [f'JSON Doc {token}', f'CSV Doc {token}', f'XML Doc {token}']
contents = [f'json content {token}', f'csv content {token}', f'xml content {token}']

json_bytes = json.dumps([{'title': titles[0], 'content': contents[0]}]).encode()
csv_buffer = io.StringIO(newline='')
writer = csv.writer(csv_buffer, lineterminator='\n')
writer.writerow(['title', 'content'])
writer.writerow([titles[1], contents[1]])
csv_bytes = csv_buffer.getvalue().encode()
xml_bytes = f'<docs><doc><title>{titles[2]}</title><content>{contents[2]}</content></doc></docs>'.encode()

safe_files = {
    f'dynamic_{token}.json': json_bytes,
    f'dynamic_{token}.csv': csv_bytes,
    f'dynamic_{token}.xml': xml_bytes,
}
relative_escape = Path(f'/home/user/dynamic_relative_{token}.txt')
absolute_escape = Path(f'/home/user/dynamic_absolute_{token}.txt')
trick_escape = Path(f'/home/user/dynamic_trick_{token}.txt')
escape_paths = [relative_escape, absolute_escape, trick_escape]
for path in escape_paths:
    if path.exists() or path.is_symlink():
        path.unlink()

archive = Path('/home/user/incoming_docs.tar.gz')
with tarfile.open(archive, 'w:gz') as tf:
    for name, data in safe_files.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))

    malicious = {
        f'../dynamic_relative_{token}.txt': b'relative escape',
        str(absolute_escape): b'absolute escape',
        f'subdir/../../dynamic_trick_{token}.txt': b'trick escape',
    }
    for name, data in malicious.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))

for path in [Path('/home/user/docs_raw'), Path('/home/user/docs_md')]:
    if path.exists() or path.is_symlink():
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()
report_path = Path('/home/user/report.json')
if report_path.exists() or report_path.is_symlink():
    report_path.unlink()

result = subprocess.run(
    [sys.executable, str(script)],
    cwd='/home/user',
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=30,
)
assert result.returncode == 0, f'build_docs.py failed on a fresh archive.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'

raw_dir = Path('/home/user/docs_raw')
md_dir = Path('/home/user/docs_md')
assert raw_dir.is_dir(), 'build_docs.py did not create docs_raw.'
assert md_dir.is_dir(), 'build_docs.py did not create docs_md.'
assert report_path.is_file(), 'build_docs.py did not create report.json.'

raw_regular_files = {str(p.relative_to(raw_dir)) for p in raw_dir.rglob('*') if p.is_file()}
assert raw_regular_files == set(safe_files), f'Unexpected extracted files: {raw_regular_files}'
for name, expected in safe_files.items():
    assert (raw_dir / name).read_bytes() == expected, f'Extracted content mismatch for {name}'

for path in escape_paths:
    assert not path.exists(), f'Tar slip vulnerability created {path}'

expected_md = {
    title.replace(' ', '_') + '.md': f'# {title}\n\n{content}'
    for title, content in zip(titles, contents)
}
actual_md_files = {p.name for p in md_dir.iterdir() if p.is_file()}
assert actual_md_files == set(expected_md), f'Markdown files mismatch: {actual_md_files}'
for name, expected in expected_md.items():
    actual = (md_dir / name).read_text(encoding='utf-8')
    assert actual.strip() == expected.strip(), f'Markdown content mismatch in {name}'

with report_path.open(encoding='utf-8') as f:
    report = json.load(f)
assert set(report) == {'skipped_members', 'extracted_files', 'generated_md_files'}, 'report.json keys mismatch.'
for key in report:
    assert isinstance(report[key], int) and not isinstance(report[key], bool), f'{key} must be an integer.'
assert report['skipped_members'] == 3, report
assert report['extracted_files'] == 3, report
assert report['generated_md_files'] == 3, report
DYNAMIC_EOF

ok=1
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_dynamic_execution.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
