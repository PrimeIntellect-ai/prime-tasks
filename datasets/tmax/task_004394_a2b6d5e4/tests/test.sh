#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid
import pytest

LEGACY = Path("/home/user/legacy_docs.json")
UTF8 = Path("/home/user/docs_utf8.json")
DIST = Path("/home/user/dist")
VENDOR = Path("/app/vendor/pydocorg-1.2.0")


def source_articles():
    with LEGACY.open("r", encoding="windows-1252") as f:
        return json.load(f)


def test_utf8_conversion():
    utf8_file = "/home/user/docs_utf8.json"
    assert os.path.exists(utf8_file), f"Converted file {utf8_file} does not exist."
    assert os.path.isfile(utf8_file), f"Path {utf8_file} is not a file."

    try:
        with open(utf8_file, "r", encoding="utf-8") as f:
            content = f.read()
            # The original file had 'Caf\xe9' in Windows-1252, which is 'Café' in UTF-8
            assert "Café" in content, f"Expected 'Café' not found in {utf8_file}. Conversion might be incorrect."
    except UnicodeDecodeError:
        pytest.fail(f"File {utf8_file} is not a valid UTF-8 encoded file.")

    with UTF8.open("r", encoding="utf-8") as f:
        converted = json.load(f)
    assert converted == source_articles(), "The UTF-8 JSON is not a faithful conversion of legacy_docs.json."


def test_generated_articles_and_expected_tags():
    articles = source_articles()
    articles_dir = DIST / "articles"
    tags_dir = DIST / "tags"
    assert articles_dir.is_dir(), f"Articles directory {articles_dir} does not exist."
    assert tags_dir.is_dir(), f"Tags directory {tags_dir} does not exist. Did you run the pipeline?"

    expected_article_paths = {articles_dir / f"{article['id']}.md" for article in articles}
    actual_article_paths = set(articles_dir.glob("*.md"))
    assert actual_article_paths == expected_article_paths, "Generated article files do not match the supplied JSON."

    for article in articles:
        article_path = articles_dir / f"{article['id']}.md"
        assert article_path.is_file() and not article_path.is_symlink()
        expected_content = f"# {article['title']}\n\n{article['body']}"
        assert article_path.read_text(encoding="utf-8") == expected_content

    expected_links = {
        tags_dir / str(tag) / f"{article['id']}.md"
        for article in articles
        for tag in article.get("tags", [])
    }
    actual_links = set(tags_dir.glob("**/*.md"))
    assert actual_links == expected_links, "Generated tag entries do not match the tags in the supplied JSON."

    for link in expected_links:
        assert link.is_symlink(), f"Expected {link} to be a symbolic link."
        expected_article = articles_dir / link.name
        expected_target = os.path.relpath(expected_article, start=link.parent)
        assert os.readlink(link) == expected_target, f"{link} has an incorrect relative target."
        assert link.resolve(strict=True) == expected_article.resolve(strict=True)


def test_symlink_validity_metric():
    tags_dir = "/home/user/dist/tags"
    assert os.path.exists(tags_dir), f"Tags directory {tags_dir} does not exist. Did you run the pipeline?"

    symlinks = glob.glob(f"{tags_dir}/**/*.md", recursive=True)

    assert len(symlinks) > 0, f"No symlinks found in {tags_dir}. The pipeline might have failed to generate output."

    valid_count = sum(1 for link in symlinks if os.path.exists(os.path.realpath(link)))
    score = (valid_count / len(symlinks)) * 100.0

    assert score >= 100.0, f"Symlink Validity Score is {score}%, expected >= 100.0%. Some symlinks are broken."


def test_patched_vendored_pipeline_on_fresh_input():
    assert (VENDOR / "pydocorg" / "linker.py").is_file(), "Vendored linker.py is missing."
    nonce = uuid.uuid4().hex
    test_data = [
        {
            "id": f"verify_{nonce}",
            "title": "Verifier Café",
            "body": "Fresh pipeline execution",
            "tags": [f"tag_{nonce}", f"other_{nonce}"],
        }
    ]

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        input_path = tmp_path / "input.json"
        output_path = tmp_path / "dist"
        input_path.write_text(json.dumps(test_data, ensure_ascii=False), encoding="utf-8")

        env = os.environ.copy()
        env["PYTHONPATH"] = str(VENDOR)
        subprocess.run(
            [sys.executable, "-m", "pydocorg.cli", "build", "--input", str(input_path), "--output", str(output_path)],
            check=True,
            env=env,
            timeout=30,
        )

        article = output_path / "articles" / f"verify_{nonce}.md"
        assert article.is_file()
        assert article.read_text(encoding="utf-8") == "# Verifier Café\n\nFresh pipeline execution"
        for tag in test_data[0]["tags"]:
            link = output_path / "tags" / tag / article.name
            assert link.is_symlink(), f"Fresh build did not create symlink {link}."
            assert os.readlink(link) == os.path.relpath(article, start=link.parent)
            assert link.resolve(strict=True) == article.resolve(strict=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
