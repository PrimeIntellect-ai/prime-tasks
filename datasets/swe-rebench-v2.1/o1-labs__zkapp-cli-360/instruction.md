Update "networks" in config.json to "deployAliases"
We've changed term for this from 'network' to 'deploy alias' for clarity, based on feedback from devs. But we still need to update this in the code.

- [ ] [Here](https://github.com/o1-labs/zkapp-cli/blob/main/templates/project-ts/config.json)
- [ ] needs changes in the deploy.js file to test for which property exists when reading from the file, so we can support both

### Additional contract requirements

- The project TypeScript template config at `templates/project-ts/config.json` must use the key `deployAliases` (an empty object) and must not use the legacy key `networks`.
- `deploy()` in `src/lib/deploy.js` must accept a `config.json` that uses either the legacy `networks` key or the new `deployAliases` key. In particular, when `config.json` uses the legacy `networks` key, `deploy()` must resolve the deploy alias from it instead of failing.

- If a deploy alias has no configured smart contract and the build contains exactly one contract, deployment must use that contract.
- If a deploy alias has no configured smart contract and the build contains multiple contracts, selection must remain falsy so the caller can ask the user to choose.
