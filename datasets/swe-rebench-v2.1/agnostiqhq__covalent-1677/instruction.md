Determine if covalent subprocess starts successfully
## Description

The covalent CLI currently starts a FastAPI server as a subprocess when `covalent start` is invoked, the PID is persisted to disk subsequently and `covalent status` just checks the existence of this PID file.

> The relevant methods can be found in: `covalent_dispacther._cli.service.py`

Any errors that may be present when starting the subprocess are currently suppressed and the PID file is persisted even if the subprocess fails to start. As a result we want to then:

- Not persist the PID file if the subprocess failed to start (so `covalent status` does not get confused)
- Display the subprocess error to the end user (more on UX below)
- Enhance `covalent status` to determine if the covalent process is stopped, swapped out of memory, or in a zombie state
