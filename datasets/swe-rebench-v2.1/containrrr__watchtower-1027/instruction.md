Watchtower causes a cron crash on Ubuntu when checking for updates
When watchtower runs to check for updates, I receive the following errors in my log, which seems to have two problems:

The first seems similar to Issue #215, however this is running on Ubuntu, not Synology.
The 2nd and more major issue is that there is a crash upon checking for an update for various containers..

How can I address/fix these issues?

Watchtower used to update all my containers correctly, but sometime recently has stopped working.

I've tried:
"sudo docker images --digest --all" to find the image listed in the log, to no avail
"sudo docker image prune -a" to delete the offending image (even though it wasn't listed) to no avail
Stopping all containers except for watchtower and portainer, and portainer was updated successfully.
I've tried adding the "--include-stopped & --revive-stopped" command line switches to update stopped containers and still receive the same crash.
It's not always the same container that the crash happens directly after. I've seen it crash right after gaps, netdata and portainer

Can someone help me out please?
Thanks


```
time="2021-07-20T11:18:49+10:00" level=warning msg="Failed to retrieve container image info: Error: No such image: sha256:df88b5138fbaaa7cb50ec3b6bbcff56f530c38629f92d92e487efd77f271adba",
time="2021-07-20T11:19:02+10:00" level=info msg="Found new linuxserver/nzbget:latest image (aabc8e4566c5)",
time="2021-07-20T11:19:04+10:00" level=info msg="Found new ghcr.io/linuxserver/sonarr:latest image (f53874960155)",
time="2021-07-20T11:19:06+10:00" level=info msg="Found new ghcr.io/linuxserver/mariadb:latest image (5ffe6d171e1b)",
time="2021-07-20T11:19:14+10:00" level=info msg="Found new housewrecker/gaps:latest image (e01f3c5a9767)",
time="2021-07-20T11:19:21+10:00" level=info msg="Found new netdata/netdata:latest image (19e491d9bf01)",
2021/07/20 11:19:23 cron: panic running job: runtime error: invalid memory address or nil pointer dereference,
goroutine 218 [running]:,
github.com/robfig/cron.(*Cron).runWithRecovery.func1(0xc000322690),
	/home/runner/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:161 +0x9e,
panic(0xc1cc60, 0x1246f20),
	/opt/hostedtoolcache/go/1.15.11/x64/src/runtime/panic.go:969 +0x1b9,
github.com/containrrr/watchtower/pkg/registry/digest.CompareDigest(0xe04940, 0xc0004debe0, 0x0, 0x0, 0x0, 0x0, 0x0),
	/home/runner/work/watchtower/watchtower/pkg/registry/digest/digest.go:43 +0x1e4,
github.com/containrrr/watchtower/pkg/container.dockerClient.PullImage(0xe09360, 0xc00039a780, 0x1010001, 0x0, 0x0, 0xdf9920, 0xc0000384e8, 0xc000470000, 0xc0003167e0, 0x0, ...),
	/home/runner/work/watchtower/watchtower/pkg/container/client.go:315 +0x4dc,
github.com/containrrr/watchtower/pkg/container.dockerClient.IsContainerStale(0xe09360, 0xc00039a780, 0x1010001, 0x0, 0x0, 0xc0003e0000, 0xc0003167e0, 0x0, 0x9e00bc, 0xc162a0, ...),
	/home/runner/work/watchtower/watchtower/pkg/container/client.go:267 +0xae,
github.com/containrrr/watchtower/internal/actions.Update(0xe01ac0, 0xc0003d8780, 0xc0003e80b0, 0x1, 0x2540be400, 0x0, 0x0, 0x0, 0x0),
	/home/runner/work/watchtower/watchtower/internal/actions/update.go:34 +0x1c8,
github.com/containrrr/watchtower/cmd.runUpdatesWithNotifications(0xc0003e80b0, 0xc000014460),
	/home/runner/work/watchtower/watchtower/cmd/root.go:334 +0xde,
github.com/containrrr/watchtower/cmd.runUpgradesOnSchedule.func1(),
	/home/runner/work/watchtower/watchtower/cmd/root.go:289 +0xb6,
github.com/robfig/cron.FuncJob.Run(0xc000293ae0),
	/home/runner/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:92 +0x25,
github.com/robfig/cron.(*Cron).runWithRecovery(0xc000322690, 0xde8860, 0xc000293ae0),
	/home/runner/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:165 +0x59,
created by github.com/robfig/cron.(*Cron).run,
	/home/runner/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:199 +0x76a,
```
