# /// script
# requires-python = ">=3.12"
# dependencies = ["harbor>=0.24"]
# ///
"""Verify the pinned APEX-Agents export and apply the credential transport fix."""

import argparse
import asyncio
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ORG = "mercor"
NAME = "apex-agents-1-1"
TAG = "1.1.1"
DATASET_HASH = "3fe2900ebd603ea5a802049819ce6ead171575ee0166a61187065ad9606c955d"
EXPECTED_TASKS = 240
DESTINATION = Path(__file__).resolve().parents[2] / "datasets/apex-agents"
LOCAL_MODIFICATIONS = [
    "tests/grade.py: pass grading settings to the runner over stdin instead of "
    "writing judge credentials to a temporary JSON file"
]


def patch_grader(task_dir: Path) -> None:
    """Apply the same narrow patch after validating the upstream content hash."""
    path = task_dir / "tests/grade.py"
    source = path.read_text()
    replacements = (
        ('        "grading_settings.json": json.dumps(judge_settings(config)),\n', ""),
        (
            '        "--grading-settings", str(workdir / "grading_settings.json"),',
            '        "--grading-settings", "/dev/stdin",',
        ),
        (
            "    result = subprocess.run(command, cwd=GRADING_PROJECT)",
            "    # Keep judge credentials off disk; the runner reads this pipe as JSON.\n"
            "    result = subprocess.run(\n"
            "        command, cwd=GRADING_PROJECT,\n"
            "        input=json.dumps(judge_settings(config)), text=True,\n"
            "    )",
        ),
    )
    for before, after in replacements:
        if source.count(before) != 1:
            raise ValueError(f"{path}: upstream grader no longer matches the stdin patch")
        source = source.replace(before, after)
    path.write_text(source)


def export_from_harbor(output_dir: Path) -> Path:
    harbor_bin = (
        shutil.which("harbor", path=str(Path(sys.executable).parent)) or "harbor"
    )
    subprocess.run(
        [
            harbor_bin,
            "download",
            f"{ORG}/{NAME}@{TAG}",
            "--export",
            "-o",
            str(output_dir),
        ],
        check=True,
    )
    return output_dir / NAME


async def fetch_manifest() -> tuple[str, list[tuple[str, str]]]:
    from harbor.db.client import RegistryDB

    db = RegistryDB()
    _, version = await db.resolve_dataset_version(ORG, NAME, TAG)
    if version.get("content_hash") != DATASET_HASH:
        raise ValueError(
            f"Expected dataset hash {DATASET_HASH}, got {version.get('content_hash')}"
        )
    rows = await db.get_dataset_version_tasks(version["id"])
    tasks = sorted(
        (row.task_version.package.name, row.task_version.content_hash) for row in rows
    )
    if len(tasks) != EXPECTED_TASKS:
        raise ValueError(f"Expected {EXPECTED_TASKS} tasks, got {len(tasks)}")
    return str(version["version"]), tasks


def main() -> None:
    from harbor.publisher.packager import Packager

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        help="Existing Harbor export directory to verify and copy",
    )
    args = parser.parse_args()

    version, expected_tasks = asyncio.run(fetch_manifest())
    DESTINATION.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        source_root = (
            args.source.resolve()
            if args.source is not None
            else export_from_harbor(Path(tmp))
        )
        if (source_root / NAME).is_dir() and not (
            source_root / expected_tasks[0][0]
        ).is_dir():
            source_root = source_root / NAME

        actual_dirs = sorted(p.name for p in source_root.iterdir() if p.is_dir())
        expected_names = [name for name, _ in expected_tasks]
        if actual_dirs != expected_names:
            raise ValueError("Source task directories do not match upstream manifest")

        records = []
        for task_name, expected_hash in expected_tasks:
            src_task = source_root / task_name
            computed_hash, collected = Packager.compute_content_hash(src_task)
            if computed_hash != expected_hash:
                raise ValueError(
                    f"{task_name}: expected hash {expected_hash}, got {computed_hash}"
                )
            all_files = {p.resolve() for p in src_task.rglob("*") if p.is_file()}
            if all_files != set(collected):
                raise ValueError(
                    f"{task_name}: unexpected uncollected files in source export"
                )
            dst_task = DESTINATION / task_name
            if dst_task.exists():
                shutil.rmtree(dst_task)
            shutil.copytree(src_task, dst_task)
            patch_grader(dst_task)
            exported_hash, _ = Packager.compute_content_hash(dst_task)
            records.append({
                "name": task_name,
                "content_hash": computed_hash,
                "exported_content_hash": exported_hash,
            })

    provenance = {
        "dataset": f"{ORG}/{NAME}",
        "tag": TAG,
        "version": version,
        "content_hash": DATASET_HASH,
        "license": "CC-BY-4.0",
        "local_modifications": LOCAL_MODIFICATIONS,
        "tasks": records,
    }
    (DESTINATION / "provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n"
    )
    print(f"Exported and verified {len(records)} tasks to {DESTINATION}")


if __name__ == "__main__":
    main()
