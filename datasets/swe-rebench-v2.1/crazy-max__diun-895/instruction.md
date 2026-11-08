[Feature] Do not launch update checks at startup
### Support guidelines

- [X] I've read the [support guidelines](https://github.com/crazy-max/diun/blob/master/.github/SUPPORT.md)

### I've found a bug and checked that ...

- [X] ... the documentation does not mention anything about my problem
- [X] ... there are no open or closed issues that are related to my problem

### Description

At container startup, Diun lauches the update check, as it is explained in the comment https://github.com/crazy-max/diun/issues/833#issuecomment-1586332791.
In my use case, my container is stopped every night because installed on Synolog NAS that shutdown every night, and every morning Diun check updates, despite i set it up to check only on sundays.

### Expected behaviour

Add a new config parameter to activate or not the run at startup in addition with the cron trigger.

### Actual behaviour

Run is launched at startup and when triggered by cron.

### Steps to reproduce

1. Start Diun container
2. Check is done immediatly even if the moment does not satisfy the cron

### Diun version

4.24.0

### Docker info

```text
Client:
 Context:    default
 Debug Mode: false

Server:
 Containers: 17
  Running: 15
  Paused: 0
  Stopped: 2
 Images: 33
 Server Version: 20.10.3
 Storage Driver: btrfs
  Build Version: Btrfs v4.0
  Library Version: 101
 Logging Driver: db
 Cgroup Driver: cgroupfs
 Cgroup Version: 1
 Plugins:
  Volume: local
  Network: bridge host ipvlan macvlan null overlay
  Log: awslogs db fluentd gcplogs gelf journald json-file local logentries splunk syslog
 Swarm: inactive
 Runtimes: io.containerd.runc.v2 io.containerd.runtime.v1.linux runc
 Default Runtime: runc
 Init Binary: docker-init
 containerd version: 3fa00912415f3e9c6f82dd72119179d599efd13b
 runc version: 31cc25f16f5eba4d0f53e35374532873744f4b31
 init version: ed96d00 (expected: de40ad0)
 Security Options:
  apparmor
 Kernel Version: 4.4.180+
 OSType: linux
 Architecture: x86_64
 CPUs: 2
 Total Memory: 5.641GiB
 Name: SkuairStation
 ID: DGMR:ZSA2:HDUM:REYZ:EILQ:YXMF:IW7K:XNCW:LDI7:CT6U:NSZS:DKGV
 Docker Root Dir: /volume1/@docker
 Debug Mode: false
 Registry: https://index.docker.io/v1/
 Labels:
 Experimental: false
 Insecure Registries:
  127.0.0.0/8
 Live Restore Enabled: false
```


### Docker Compose config

_No response_

### Logs

```text
2023-06-08T05:33:43.375570918Z | stdout | �[90mThu, 08 Jun 2023 07:33:43 CEST�[0m �[32mINF�[0m Next run in 2 days 16 hours (2023-06-11 00:30:09.977184317 +0200 CEST)
-- | -- | --
2023-06-08T05:33:43.375482822Z | stdout | �[90mThu, 08 Jun 2023 07:33:43 CEST�[0m �[32mINF�[0m Cron initialized with schedule 30 0 * * 0
2023-06-08T05:33:43.375026847Z | stdout | �[90mThu, 08 Jun 2023 07:33:43 CEST�[0m �[32mINF�[0m Jobs completed �[36madded=�[0m0 �[36mfailed=�[0m0 �[36mskipped=�[0m0 �[36munchanged=�[0m13 �[36mupdated=�[0m2
2023-06-08T05:33:21.636264725Z | stdout | �[90mThu, 08 Jun 2023 07:33:21 CEST�[0m �[32mINF�[0m Image update found �[36mimage=�[0mdocker.io/linuxserver/pyload-ng:latest �[36mprovider=�[0mdocker
2023-06-08T05:33:21.143026694Z | stdout | �[90mThu, 08 Jun 2023 07:33:21 CEST�[0m �[32mINF�[0m Image update found �[36mimage=�[0mdocker.io/gitea/gitea:latest �[36mprovider=�[0mdocker
2023-06-08T05:33:17.557081854Z | stdout | �[90mThu, 08 Jun 2023 07:33:17 CEST�[0m �[32mINF�[0m Found 15 image(s) to analyze �[36mprovider=�[0mdocker
2023-06-08T05:33:02.548833910Z | stdout | �[90mThu, 08 Jun 2023 07:33:02 CEST�[0m �[32mINF�[0m Cron triggered
2023-06-08T05:32:59.547710032Z | stdout | �[90mThu, 08 Jun 2023 07:32:59 CEST�[0m �[32mINF�[0m Configuration loaded from 1 environment variable(s)
2023-06-08T05:32:59.547617557Z | stdout | �[90mThu, 08 Jun 2023 07:32:59 CEST�[0m �[32mINF�[0m Configuration loaded from file: /diun.yml
2023-06-08T05:32:59.106430652Z | stdout | �[90mThu, 08 Jun 2023 07:32:59 CEST�[0m �[32mINF�[0m Starting Diun �[36mversion=�[0mv4.24.0
2023-06-07T23:00:22.571237010Z | stdout | �[90mThu, 08 Jun 2023 01:00:22 CEST�[0m �[31mWRN�[0m Caught signal terminated
```


### Additional info

_No response_

### Additional contract requirements

Expose this option as YAML `watch.runOnStartup` and as the Go configuration field `Watch.RunOnStartup`. When enabled, Diun runs an update check at startup; when disabled, it does not run a startup check. Disabling the startup check must not disable update checks triggered by the configured schedule. The startup check may complete after startup returns.
