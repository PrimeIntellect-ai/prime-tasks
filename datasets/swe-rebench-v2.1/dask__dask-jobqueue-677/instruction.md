Job script epilogue
Would be nice to have `job_script_prologue` equivalent but for cleanup. I.e. run some commands after worker exists. The argument could be called `job_script_epilogue`.

### Additional contract requirements

Provide a `job_script_epilogue` argument for cleanup commands. Commands supplied through it must appear in the generated job script after the worker command has completed.
