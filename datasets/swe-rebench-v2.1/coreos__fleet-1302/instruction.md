fleetd no longer has default etcd endpoints
since approximately 30f9f1f3ef73a118a691ac67188b14506cdce3a3, fleetd no longer has default etcd endpoints, resulting in fleetd exiting if no configuration is specified.

```
Jul 09 22:03:22 localhost systemd[1]: Started fleet daemon.
Jul 09 22:03:22 localhost systemd[1]: Starting fleet daemon...
Jul 09 22:03:22 localhost fleetd[566]: INFO fleetd.go:64: Starting fleetd version 0.11.0
Jul 09 22:03:22 localhost fleetd[566]: INFO fleetd.go:168: No provided or default config file found - proceeding without
Jul 09 22:03:22 localhost fleetd[566]: FATAL fleetd.go:90: Failed creating Server: client: no endpoints available
Jul 09 22:03:22 localhost systemd[1]: fleet.service: Main process exited, code=exited, status=1/FAILURE
Jul 09 22:03:22 localhost systemd[1]: fleet.service: Unit entered failed state.
Jul 09 22:03:22 localhost systemd[1]: fleet.service: Failed with result 'exit-code'.
```

### Additional contract requirements

When no configuration supplies etcd endpoints, fleetd must use a nonempty default endpoint list so that it does not fail because no etcd endpoints are available.
