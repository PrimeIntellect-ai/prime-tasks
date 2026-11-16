specconv.CreateLibcontainerConfig doesn't honor spec.Process.NoNewPrivileges
If the passed in `opts` to `CreateLibcontainerConfig` specifies the `NoNewPrivileges` flag under `Process`, it is not honored and the generated config doesn't set the flag appropriately.
