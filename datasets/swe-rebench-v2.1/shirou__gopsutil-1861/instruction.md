Mount options does not split by comma
**Describe the bug**
In `PartitionsWithContext()`, the value of`PartitionStat.Opts` doesn't use `,` when splition. So the options are in one string. As contrast, mount options are split when using `/proc/1/mountinfo`.
https://github.com/shirou/gopsutil/blob/34ac457e154c695cf35ed79ffa15eb0966c650bb/disk/disk_linux.go#L292-L325

**To Reproduce**
```go
package main

import (
	"fmt"

	"github.com/shirou/gopsutil/v4/disk"
)

func main() {
	partitions, err := disk.Partitions(true)
	if err != nil {
		log.Fatalln(err)
	}
	for _, each := range partitions {
		fmt.Printf("+%v\n", each)
	}
}
```

**Expected behavior**
Mount options of each mountpoint should be split by `,`.

**Environment (please complete the following information):**
 - [ ] Windows: [paste the result of `ver`]
 - [x] Linux:
 - [ ] Mac OS: [paste the result of `sw_vers` and `uname -a`
 - [ ] FreeBSD: [paste the result of `freebsd-version -k -r -u` and  `uname -a`]
 - [ ] OpenBSD: [paste the result of `uname -a`]

**Additional context**
