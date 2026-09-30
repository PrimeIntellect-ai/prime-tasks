"""Validate external release inputs before starting submission grading."""
import json
import sys
import urllib.error
import urllib.request


def check():
    errors = []
    for repository in (
        "axodotdev/oranda",
        "axodotdev/axolotlsay",
        "oranda-gallery/oranda-inference-test",
    ):
        attempts = []
        for url in (
            f"https://octolotl.axodotdev.host/releases/{repository}",
            f"https://api.github.com/repos/{repository}/releases",
        ):
            try:
                request = urllib.request.Request(url, headers={"User-Agent": "octolotl-0.1.1"})
                with urllib.request.urlopen(request, timeout=8) as response:
                    data = json.load(response)
                if not isinstance(data, list) or not data:
                    raise ValueError("release fixture is empty or malformed")
                break
            except (urllib.error.URLError, TimeoutError, ValueError) as exc:
                attempts.append(f"{url}: {exc}")
        else:
            errors.extend(attempts)
    if errors:
        print("Release fixture service is unavailable; grading must not start.\n" + "\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(check())
