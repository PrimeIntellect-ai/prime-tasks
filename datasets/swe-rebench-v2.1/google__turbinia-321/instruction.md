turbinia_job_graph.py doesn't support new job manager
turbinia_job_graph.py needs to be updated to support the new job manager (from #257).

### Additional contract requirements

- The job graph tool in `tools/turbinia_job_graph.py` must work with the current job manager (`turbinia.jobs.manager.JobsManager`). Calling its `create_graph()` function must succeed and return a graphviz `Digraph` describing every job registered with the job manager.
- Each registered job appears as a node named after the job's `NAME`. Each evidence type listed in the job's `evidence_input` and `evidence_output` appears as a node named after the evidence class.
- Every evidence type in a job's `evidence_input` has an edge from that evidence node to the job node. Every evidence type in a job's `evidence_output` has an edge from the job node to that evidence node.
