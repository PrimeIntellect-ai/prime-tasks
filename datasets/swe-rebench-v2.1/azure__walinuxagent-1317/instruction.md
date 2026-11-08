CGroups error in Ubuntu 14.04
```
2018/07/31 11:41:06.400633 ERROR ExtHandler monitor: Exception tracking wrapper and agent: 'Hierarchy memory is not mounted' [Traceback (most recent call last):
  File "bin/WALinuxAgent-2.2.30-py2.7.egg/azurelinuxagent/ga/monitor.py", line 397, in init_cgroups
    CGroupsTelemetry.track_cgroup(CGroups.for_extension(""))
  File "bin/WALinuxAgent-2.2.30-py2.7.egg/azurelinuxagent/common/cgroups.py", line 360, in for_extension
    return CGroups(name, CGroups._construct_custom_path_for_hierarchy)
  File "bin/WALinuxAgent-2.2.30-py2.7.egg/azurelinuxagent/common/cgroups.py", line 401, in __init__
    raise CGroupsException("Hierarchy {0} is not mounted".format(hierarchy))
azurelinuxagent.common.cgroups.CGroupsException: 'Hierarchy memory is not mounted'
]
```

### Additional contract requirements

- When cgroups cannot be initialized because the memory hierarchy is not mounted, the agent must not report that condition as an error-level log entry.
