#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import tarfile
from pathlib import Path

SCRIPT = Path('/home/user/l10n_pipeline.py')
SOURCE = Path('/tmp/remote_l10n_source')
GLOSSARY = Path('/home/user/glossary.csv')
PROCESSED = Path('/home/user/processed_l10n')
LOG = Path('/home/user/pipeline.log')
TARBALL = Path('/tmp/remote_l10n_dest/l10n_release.tar.gz')


def load_inputs():
    languages = {}
    for path in sorted(SOURCE.glob('*.json')):
        with path.open(encoding='utf-8') as f:
            languages[path.stem] = json.load(f)
    with GLOSSARY.open(newline='', encoding='utf-8') as f:
        glossary = {(row['id'], row['lang']): row['text'] for row in csv.DictReader(f)}
    return languages, glossary


def expected_outputs(languages, glossary):
    english = languages['en']
    result = {}
    imputed = {}
    for lang, rows in languages.items():
        by_id = {row['id']: row for row in rows}
        groups = {}
        count = 0
        for source_row in english:
            ident = source_row['id']
            if lang == 'en':
                text = source_row['text']
            else:
                existing = by_id.get(ident)
                text = None if existing is None else existing.get('text')
                if text is None or text == '':
                    count += 1
                    text = glossary.get((ident, lang), '[TBD] ' + source_row['text'])
            groups.setdefault(source_row['context'], []).append({'id': ident, 'text': text})
        for values in groups.values():
            values.sort(key=lambda obj: obj['id'])
        result[lang] = groups
        if lang != 'en':
            imputed[lang] = count
    return result, imputed


def test_pipeline_end_to_end():
    assert SCRIPT.is_file(), f'Required script {SCRIPT} does not exist'

    # Remove all generated artifacts, then require the submitted script to recreate them.
    if PROCESSED.exists():
        import shutil
        shutil.rmtree(PROCESSED)
    for path in (LOG, TARBALL):
        if path.exists():
            path.unlink()

    completed = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'Pipeline failed with exit code {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )

    languages, glossary = load_inputs()
    expected, imputed = expected_outputs(languages, glossary)

    assert PROCESSED.is_dir(), f'{PROCESSED} was not created'
    expected_paths = {
        f'{lang}/{context}.json'
        for lang, groups in expected.items()
        for context in groups
    }
    actual_paths = {
        str(path.relative_to(PROCESSED))
        for path in PROCESSED.rglob('*')
        if path.is_file()
    }
    assert actual_paths == expected_paths

    for lang, groups in expected.items():
        for context, expected_data in groups.items():
            path = PROCESSED / lang / f'{context}.json'
            raw = path.read_text(encoding='utf-8')
            assert json.loads(raw) == expected_data, f'Incorrect contents in {path}'
            # Enforce standard json.dump(..., indent=2)-style formatting.
            assert raw == json.dumps(expected_data, indent=2) or raw == json.dumps(expected_data, indent=2) + '\n', \
                f'{path} does not use standard 2-space JSON formatting'

    assert LOG.is_file(), f'{LOG} was not created'
    log_content = LOG.read_text(encoding='utf-8')
    for lang in languages:
        assert f'INFO: Processing language {lang}' in log_content
        assert f'INFO: Exported {len(expected[lang])} context groups for {lang}' in log_content
        if lang != 'en':
            assert f'WARNING: Imputed {imputed[lang]} missing keys for {lang}' in log_content

    assert TARBALL.is_file(), f'{TARBALL} was not deployed'
    assert tarfile.is_tarfile(TARBALL), f'{TARBALL} is not a valid tar archive'
    with tarfile.open(TARBALL, 'r:gz') as tar:
        members = [member for member in tar.getmembers() if member.isfile()]
        archived_paths = set()
        for member in members:
            parts = Path(member.name).parts
            assert '..' not in parts and not Path(member.name).is_absolute()
            matches = [i for i, part in enumerate(parts) if part == 'processed_l10n']
            if matches:
                rel = Path(*parts[matches[-1] + 1:])
            else:
                rel = Path(*parts)
            archived_paths.add(str(rel))
            extracted = tar.extractfile(member)
            assert extracted is not None
            disk_path = PROCESSED / rel
            assert disk_path.is_file(), f'Unexpected archive member {member.name}'
            assert extracted.read() == disk_path.read_bytes(), f'Archive member {member.name} differs from processed output'
        assert archived_paths == expected_paths, 'Archive does not contain the complete processed directory'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
