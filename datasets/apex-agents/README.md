# APEX-Agents 1.1

240 Harbor tasks exported from [`mercor/apex-agents-1-1@1.1.1`](https://hub.harborframework.com/datasets/mercor/apex-agents-1-1) (version `4.0.1`, dataset digest `sha256:3fe2900ebd603ea5a802049819ce6ead171575ee0166a61187065ad9606c955d`), with the credential transport patch described below.

- **Domains:** 80 Investment Banking, 80 Law, and 80 Management Consulting tasks across 31 worlds.
- **Sources:** [Mercor blog](https://www.mercor.com/blog/introducing-apex-agents-1-1/), [paper](https://arxiv.org/abs/2601.14242), [Hugging Face](https://huggingface.co/datasets/mercor/apex-agents-v1.1), and [reference agent](https://github.com/Mercor-Intelligence/apex_loop_truncated_tools_agent).
- **License:** [CC-BY 4.0](LICENSE) (Akul Datta, Austin Bennett, Bertie Vidgen, and Mercor). Upstream marks this benchmark for model evaluation only, not training or parameter fitting.

## Runtime images

Task instructions, prompts, compose overlays, rubrics, reference outputs, timeouts, and resource limits match the Harbor Hub export byte for byte. The sole change to each task is in `tests/grade.py`: grading settings are sent to the runner through stdin (`--grading-settings /dev/stdin`) instead of a temporary JSON file, so judge API keys are not written to disk. Judge settings and grading behavior are otherwise unchanged.

[`provenance.json`](provenance.json) records each task's upstream `content_hash` and patched `exported_content_hash`, using Harbor's content-hash algorithm. The dataset-level `content_hash` identifies the upstream dataset. The importer verifies upstream hashes before applying the patch and recording the exported hashes.

The `apex-agents` environment in `prime-envs` loads this directory pinned to a Git commit and maps the upstream container digests to public Prime VM images:

- Agent: `prime/primeintellect/apex-agents-native-main:9be28bae20bc`
- Worlds (31): `prime/primeintellect/apex-agents-native-world:<12-character upstream digest>`
- Verifiers (240): `prime/primeintellect/apex-agents-1-1-verifier.x86.<task>:1.1.1`

## Re-export and verify

```bash
uv run scripts/apex-agents/import_tasks.py
```

Run the credential-handoff regression tests with Python 3.12 or newer:

```bash
python3 -m unittest discover -s scripts/apex-agents/tests -v
```
