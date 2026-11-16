Add a function to get the timer directly from a KrylovWorkspace

### Additional contract requirements

- Provide the public accessor `krylov_elapsed_time(workspace)`, which returns the elapsed wall-clock time in seconds for the most recent solve associated with a Krylov workspace.
