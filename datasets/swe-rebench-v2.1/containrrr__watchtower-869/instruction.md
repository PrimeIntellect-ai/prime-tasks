Crash when shoutrrr notifications are enabled but no URLs are specified
**Describe the bug**
I updated to the latest version 1.2.1 but I am getting the following error

```
2021-03-29T08:52:34.143334096Z panic: runtime error: slice bounds out of range [:-2]
2021-03-29T08:52:34.143475927Z
2021-03-29T08:52:34.143505723Z goroutine 1 [running]:
2021-03-29T08:52:34.143551278Z github.com/containrrr/watchtower/pkg/notifications.(*Notifier).String(0x1585d30, 0x775a08, 0x16)
2021-03-29T08:52:34.143581778Z 	/home/runner/work/watchtower/watchtower/pkg/notifications/notifier.go:61 +0x264
2021-03-29T08:52:34.143646833Z github.com/containrrr/watchtower/cmd.writeStartupMessage(0x15ba580, 0x0, 0x0, 0xd7f48b30, 0xe, 0xbfd670, 0x7924d0, 0x3f)
2021-03-29T08:52:34.143676555Z 	/home/runner/work/watchtower/watchtower/cmd/root.go:244 +0xd8
2021-03-29T08:52:34.143720702Z github.com/containrrr/watchtower/cmd.runUpgradesOnSchedule(0x15ba580, 0x1703698, 0x7924d0, 0x3f, 0x0, 0x0)
2021-03-29T08:52:34.143765924Z 	/home/runner/work/watchtower/watchtower/cmd/root.go:282 +0x1a0
2021-03-29T08:52:34.143810090Z github.com/containrrr/watchtower/cmd.Run(0x15ba580, 0xc0f744, 0x0, 0x0)
2021-03-29T08:52:34.143837127Z 	/home/runner/work/watchtower/watchtower/cmd/root.go:188 +0x2c8
2021-03-29T08:52:34.143912329Z github.com/spf13/cobra.(*Command).execute(0x15ba580, 0x140e0f8, 0x0, 0x0, 0x15ba580, 0x140e0f8)
2021-03-29T08:52:34.143937514Z 	/home/runner/go/pkg/mod/github.com/spf13/cobra@v0.0.7/command.go:842 +0x1e8
2021-03-29T08:52:34.143989384Z github.com/spf13/cobra.(*Command).ExecuteC(0x15ba580, 0x1458070, 0x0, 0x0)
2021-03-29T08:52:34.144016939Z 	/home/runner/go/pkg/mod/github.com/spf13/cobra@v0.0.7/command.go:943 +0x250
2021-03-29T08:52:34.144061124Z github.com/spf13/cobra.(*Command).Execute(...)
2021-03-29T08:52:34.144087901Z 	/home/runner/go/pkg/mod/github.com/spf13/cobra@v0.0.7/command.go:883
2021-03-29T08:52:34.144112697Z github.com/containrrr/watchtower/cmd.Execute()
2021-03-29T08:52:34.144156271Z 	/home/runner/work/watchtower/watchtower/cmd/root.go:70 +0x20
2021-03-29T08:52:34.144182493Z main.main()
2021-03-29T08:52:34.144223140Z 	/home/runner/work/watchtower/watchtower/main.go:13 +0x14
```
here is my docker compose file

```
watchtower:
   image: containrrr/watchtower:armhf-latest
   hostname: ${DOCKERHOSTNAME}
   container_name: watchtower
   environment:
     - REPO_PASS=${WATCHTOWER_REPO_PASS}
     - REPO_USER=${WATCHTOWER_REPO_USER}
     - TZ=${TZ}
     - WATCHTOWER_CLEANUP=${WATCHTOWER_CLEANUP}
     - WATCHTOWER_INCLUDE_STOPPED=${WATCHTOWER_INCLUDE_STOPPED}
     - WATCHTOWER_MONITOR_ONLY=${WATCHTOWER_MONITOR_ONLY}
     - WATCHTOWER_NOTIFICATION_TEMPLATE=${WATCHTOWER_NOTIFICATION_TEMPLATE}
     - WATCHTOWER_NOTIFICATION_URL=${WATCHTOWER_NOTIFICATION_URL}
     - WATCHTOWER_NOTIFICATIONS_LEVEL=${WATCHTOWER_NOTIFICATIONS_LEVEL}
     - WATCHTOWER_NOTIFICATIONS=${WATCHTOWER_NOTIFICATIONS}
     - WATCHTOWER_SCHEDULE=${WATCHTOWER_SCHEDULE}
     - WATCHTOWER_TIMEOUT=${WATCHTOWER_TIMEOUT}
   logging:
     driver: json-file
     options:
       max-file: ${DOCKERLOGGING_MAXFILE}
       max-size: ${DOCKERLOGGING_MAXSIZE}
   restart: unless-stopped
   volumes:
     - /etc/localtime:/etc/localtime:ro
     - /var/run/docker.sock:/var/run/docker.sock
     - ${DOCKERSTORAGEDIR}:/storage
 ```

here the env file
```
WATCHTOWER_CLEANUP=true
WATCHTOWER_ENABLED=true
WATCHTOWER_INCLUDE_STOPPED=false
WATCHTOWER_MONITOR_ONLY=false
WATCHTOWER_NETWORK_MODE=
WATCHTOWER_NOTIFICATIONS_LEVEL=info
WATCHTOWER_NOTIFICATIONS=shoutrrr
WATCHTOWER_NOTIFICATION_TEMPLATE={{range .}}{{.Message}}{{println}}{{end}}
WATCHTOWER_NOTIFICATION_URL=
WATCHTOWER_REPO_PASS=
WATCHTOWER_REPO_USER=
WATCHTOWER_SCHEDULE=0 0 4 * * *
WATCHTOWER_TIMEOUT=40s
```

```
  `.::///+:/-.        --///+//-:``    pi@raspberrypi
 `+oooooooooooo:   `+oooooooooooo:    --------------
  /oooo++//ooooo:  ooooo+//+ooooo.    OS: Raspbian GNU/Linux 10 (buster) armv7l
  `+ooooooo:-:oo-  +o+::/ooooooo:     Host: Raspberry Pi 4 Model B Rev 1.4
   `:oooooooo+``    `.oooooooo+-      Kernel: 5.10.17-v7l+
     `:++ooo/.        :+ooo+/.`       Uptime: 18 hours, 6 mins
        ...`  `.----.` ``..           Packages: 1895 (dpkg)
     .::::-``:::::::::.`-:::-`        Shell: bash 5.0.3
    -:::-`   .:::::::-`  `-:::-       Terminal: /dev/pts/0
   `::.  `.--.`  `` `.---.``.::`      CPU: BCM2711 (4) @ 1.500GHz
       .::::::::`  -::::::::` `       Memory: 1353MiB / 7874MiB
 .::` .:::::::::- `::::::::::``::.
-:::` ::::::::::.  ::::::::::.`:::-
::::  -::::::::.   `-::::::::  ::::
-::-   .-:::-.``....``.-::-.   -::-
 .. ``       .::::::::.     `..`..
   -:::-`   -::::::::::`  .:::::`
   :::::::` -::::::::::` :::::::.
   .:::::::  -::::::::. ::::::::
    `-:::::`   ..--.`   ::::::.
      `...`  `...--..`  `...`
            .::::::::::
             `.-::::-`

```

### Additional contract requirements

- When shoutrrr notifications are enabled but no notification URLs are specified, `Notifier.String()` must return exactly `none`.
