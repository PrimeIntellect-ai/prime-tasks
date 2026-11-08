Gedis commands need to be changed to go with the new package structure
For adding nodes:
- `tfgrid.directory.nodes` + `add`/whatever function you want to call.

For farms actors:
- `tfgrid.directory.farms` + `register`/whatever function you want to call.

For querying workloads:
- `tfgrid.workloads.workload_manager` + `workloads_list`/whatever function you want to call.

### Additional contract requirements

- Use `tfgrid.workloads.workload_manager` with the `workload_get`, `workloads_list`, `set_workload_result`, and `reservation_register` commands.
