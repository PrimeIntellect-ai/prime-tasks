Make the CLI *even more* responsive
Follow-up on #56, per https://github.com/trailofbits/pip-audit/pull/87#issuecomment-954320210:

> Regarding the feedback not being great at the beginning, in the future it might be worth reporting some extra state in the PyPIProvider. Something like:

> `Gathering metadata for sdist {name} ({version})`

### Additional contract requirements

When resolving a PyPI source distribution, emit a progress-state update while gathering its metadata. The update must identify the sdist metadata-gathering phase and include the package name and version.
