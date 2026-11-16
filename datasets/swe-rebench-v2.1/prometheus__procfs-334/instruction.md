Improve CPU information for physical s390x platforms
The [current code](url) for s390x CPU doesn't provide full information for physical Z machines (as opposed to virtual Z machines). In particular `CPUInfo.CoreID` and `CPUInfo.PhysicalID` are missing (but other fields could probably be added too).

See https://bugzilla.redhat.com/show_bug.cgi?id=1882730 which has a copy of `/proc/cpuinfo` from a physical machine.
