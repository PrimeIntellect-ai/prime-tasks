#!/usr/bin/env python3
import io
import json
import os
import sys
import tarfile
import urllib.request
import uuid
from pathlib import Path

SOLUTION = Path("/solution")
GOLD = SOLUTION / "gold"
TRAJECTORY = Path("/logs/agent/trajectory.json")
WORLD_URL = os.environ.get("WORLD_URL", "http://world:8000").rstrip("/")


def populate(subsystem: str, root: Path) -> int:
    files = [path for path in root.rglob("*") if path.is_file()]
    if not files:
        return 0
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for path in files:
            archive.add(path, arcname=path.relative_to(root).as_posix())
    boundary = uuid.uuid4().hex
    body = (
        (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="archive"; filename="gold.tar.gz"\r\n'
            "Content-Type: application/gzip\r\n\r\n"
        ).encode()
        + buffer.getvalue()
        + f"\r\n--{boundary}--\r\n".encode()
    )
    request = urllib.request.Request(
        f"{WORLD_URL}/data/populate?subsystem={subsystem}",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        if response.status != 200:
            sys.exit(f"populate {subsystem} failed: HTTP {response.status}")
    return len(files)


def main() -> None:
    populated = 0
    if GOLD.is_dir():
        for subsystem in sorted(path for path in GOLD.iterdir() if path.is_dir()):
            populated += populate(subsystem.name, subsystem)
    answer = (SOLUTION / "answer.txt").read_text().strip()
    if not answer:
        sys.exit("no answer text in /solution/answer.txt")
    instruction = (SOLUTION / "instruction.md").read_text()
    TRAJECTORY.parent.mkdir(parents=True, exist_ok=True)
    TRAJECTORY.write_text(
        json.dumps(
            {
                "schema_version": "ATIF-v1.7",
                "session_id": "oracle",
                "agent": {"name": "oracle", "version": "1.0"},
                "steps": [
                    {"step_id": 1, "source": "user", "message": instruction},
                    {"step_id": 2, "source": "agent", "message": answer},
                ],
                "final_metrics": {"total_steps": 2},
                "extra": {
                    "native_status": "completed",
                    "time_elapsed_sec": 0.0,
                    "oracle_files_populated": populated,
                },
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
