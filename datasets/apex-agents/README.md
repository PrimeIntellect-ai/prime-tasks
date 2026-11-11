# APEX-Agents 1.1

240 Harbor tasks exported unmodified from [`mercor/apex-agents-1-1@1.1.1`](https://hub.harborframework.com/datasets/mercor/apex-agents-1-1) (version `4.0.1`, dataset digest `sha256:3fe2900ebd603ea5a802049819ce6ead171575ee0166a61187065ad9606c955d`).

- **Domains:** 80 Investment Banking, 80 Law, and 80 Management Consulting tasks across 31 worlds.
- **Sources:** [Mercor blog](https://www.mercor.com/blog/introducing-apex-agents-1-1/), [paper](https://arxiv.org/abs/2601.14242), [Hugging Face](https://huggingface.co/datasets/mercor/apex-agents-v1.1), and [reference agent](https://github.com/Mercor-Intelligence/apex_loop_truncated_tools_agent).
- **License:** [CC-BY 4.0](LICENSE) (Akul Datta, Austin Bennett, Bertie Vidgen, and Mercor). Upstream marks this benchmark for model evaluation only, not training or parameter fitting.

## Runtime images

Task instructions, prompts, compose overlays, rubrics, grading scripts, reference outputs, timeouts, and resource limits match the Harbor Hub export byte for byte. Per-task content hashes are recorded in [`provenance.json`](provenance.json).

The `apex-agents` environment in `prime-envs` loads this directory pinned to a Git commit and maps the upstream container digests to public Prime VM images:

- Agent: `prime/primeintellect/apex-agents-native-main:9be28bae20bc`
- Worlds (31): `prime/primeintellect/apex-agents-native-world:<12-character upstream digest>`
- Verifiers (240): `prime/primeintellect/apex-agents-1-1-verifier.x86.<task>:1.1.1`

## Re-export and verify

```bash
uv run scripts/apex-agents/import_tasks.py
```
