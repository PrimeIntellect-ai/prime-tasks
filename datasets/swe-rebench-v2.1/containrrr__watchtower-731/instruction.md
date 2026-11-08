Panic when updating an image with an additional colon: index out of range
**Describe the bug**
Execution error at time, runtime error

**To Reproduce**
docker execution with a cron configuration in environment varables

   environment:
```yaml
      TZ: "Europe/Paris"
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_DEBUG: "true"
      WATCHTOWER_NOTIFICATIONS: "email"
      WATCHTOWER_NOTIFICATION_EMAIL_FROM: "watchtower-host@mydomain"
      WATCHTOWER_NOTIFICATION_EMAIL_TO: "me@mydomain"
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER: "my.server.mydomain"
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT: 25
      WATCHTOWER_NOTIFICATION_EMAIL_DELAY: 2
      WATCHTOWER_SCHEDULE: "0 24 9 * * *"
```

**Expected behavior**
It was works while weeks like a charm.

<details>
<summary>Environment</summary>
<p>

```
docker info extract :
 Kernel Version: 5.8.0-0.bpo.2-amd64
 Operating System: Debian GNU/Linux 10 (buster)
 OSType: linux
 Architecture: x86_64
 CPUs: 4
 Total Memory: 7.653GiB
 Server Version: 20.10.1

Client: Docker Engine - Community
 Version:           20.10.1
 API version:       1.41
 Go version:        go1.13.15
 Git commit:        831ebea
 Built:             Tue Dec 15 04:34:48 2020
 OS/Arch:           linux/amd64
 Context:           default
 Experimental:      true

Server: Docker Engine - Community
 Engine:
  Version:          20.10.1
  API version:      1.41 (minimum version 1.12)
  Go version:       go1.13.15
  Git commit:       f001486
  Built:            Tue Dec 15 04:32:45 2020
  OS/Arch:          linux/amd64
  Experimental:     false
 containerd:
  Version:          1.4.3
  GitCommit:        269548fa27e0089a8b8278fc4fc781d7f65a939b
 runc:
  Version:          1.0.0-rc92
  GitCommit:        ff819c7e9184c13b7c2607fe6c30ae19403a7aff
 docker-init:
  Version:          0.19.0
  GitCommit:        de40ad0
```

</p>
</details>

<details>
 <summary><b> Logs from running watchtower with the <code>--debug</code> option </b></summary>

```
2020-12-26T09:23:07+01 [D] Sleeping for a second to ensure the docker api client has been properly initialized.
2020-12-26T09:23:08+01 [D] Retrieving running containers
2020-12-26T09:23:08+01 [D] There are no additional watchtower containers
2020-12-26T09:23:08+01 [I] Starting Watchtower and scheduling first run: 2020-12-26 09:24:00 +0100 CET
2020-12-26T09:24:00+01 [D] Checking containers for updated images
2020-12-26T09:24:00+01 [D] Retrieving running containers
2020-12-26T09:24:00+01 [D] Trying to load authentication credentials.
                           container: /watchtower_watchtower.1.lo4ykkirt3pgpu8jclno8hks0
                           image: containrrr/watchtower:latest@sha256:daf7034c5c89775afe3008393ae033529913548243b84926931d7c84398ecda7
2020-12-26T09:24:00+01 [D] No credentials for containrrr found
                           config_file: /config.json
2020-12-26T09:24:00+01 [D] Got image name: containrrr/watchtower:latest@sha256:daf7034c5c89775afe3008393ae033529913548243b84926931d7c84398ecda7
2020-12-26T09:24:00+01 [D] Checking if pull is needed
                           container: /watchtower_watchtower.1.lo4ykkirt3pgpu8jclno8hks0
                           image: containrrr/watchtower:latest@sha256:daf7034c5c89775afe3008393ae033529913548243b84926931d7c84398ecda7
2020-12-26T09:24:00+01 [D] Building challenge URL
                           URL: https://index.docker.io/v2/
2020-12-26T09:24:04+01 [D] Got response to challenge request
                           header: Bearer realm="https://auth.docker.io/token",service="registry.docker.io"
                           status: 401 Unauthorized
2020-12-26T09:24:04+01 [D] Checking challenge header content
                           realm: https://auth.docker.io/token
                           service: registry.docker.io
2020-12-26T09:24:04+01 [D] Setting scope for auth token
                           image: containrrr/watchtower
                           scope: repository:containrrr/watchtower:pull
2020-12-26T09:24:04+01 [D] No credentials found.

cron: panic running job: runtime error: index out of range [3] with length 3

goroutine 35 [running]:
github.com/robfig/cron.(*Cron).runWithRecovery.func1(0xc000076050)
	/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:161 +0x9e
panic(0xbeaa00, 0xc000250180)
	/usr/local/go/src/runtime/panic.go:969 +0x1b9
github.com/containrrr/watchtower/pkg/registry/manifest.extractImageAndTag(0xc00006a1c0, 0x64, 0x10, 0xc3a600, 0x1, 0xc000221460)
	/home/circleci/repo/pkg/registry/manifest/manifest.go:56 +0x239
github.com/containrrr/watchtower/pkg/registry/manifest.BuildManifestURL(0xd32c00, 0xc0003ba1a0, 0x0, 0x0, 0xc000137b00, 0x866)
	/home/circleci/repo/pkg/registry/manifest/manifest.go:23 +0x1a7
github.com/containrrr/watchtower/pkg/registry/digest.CompareDigest(0xd32c00, 0xc0003ba1a0, 0x0, 0x0, 0x0, 0x0, 0x0)
	/home/circleci/repo/pkg/registry/digest/digest.go:30 +0xb3
github.com/containrrr/watchtower/pkg/container.dockerClient.PullImage(0xd373e0, 0xc0000be700, 0x1, 0xd28820, 0xc000038040, 0xc0004a0000, 0xc00049e7e0, 0xc0000da840, 0x0, 0x0)
	/home/circleci/repo/pkg/container/client.go:297 +0x497
github.com/containrrr/watchtower/pkg/container.dockerClient.IsContainerStale(0xd373e0, 0xc0000be700, 0x1, 0xc0000b0000, 0xc00049e7e0, 0xc0000da840, 0x10, 0x0, 0x0)
	/home/circleci/repo/pkg/container/client.go:251 +0x9e
github.com/containrrr/watchtower/internal/actions.Update(0xd2f940, 0xc00009cda0, 0xc0000b3b90, 0x1, 0x2540be400, 0x0, 0x0, 0x0)
	/home/circleci/repo/internal/actions/update.go:30 +0x18f
github.com/containrrr/watchtower/cmd.runUpdatesWithNotifications(0xc0000b3b90)
	/home/circleci/repo/cmd/root.go:231 +0xbe
github.com/containrrr/watchtower/cmd.runUpgradesOnSchedule.func1()
	/home/circleci/repo/cmd/root.go:187 +0xb6
github.com/robfig/cron.FuncJob.Run(0xc00028d3e0)
	/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:92 +0x25
github.com/robfig/cron.(*Cron).runWithRecovery(0xc000076050, 0xd18f20, 0xc00028d3e0)
	/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:165 +0x59
created by github.com/robfig/cron.(*Cron).run
	/go/pkg/mod/github.com/robfig/cron@v0.0.0-20180505203441-b41be1df6967/cron.go:199 +0x76a

```

</details>


**Additional context**
Thanks for looking this issue and all the work done
