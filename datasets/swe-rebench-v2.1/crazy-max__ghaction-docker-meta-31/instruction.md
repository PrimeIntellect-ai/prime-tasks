Handle branch names including issue numbers correctly
### Behaviour

When using this action with branches that include issue numbers with hash signs then the tag values are generated including the hash sign. Since those are not valid tag names the further processing fails when you try to tag an image.

#### Steps to reproduce this issue

1. use this action with a branch including a hash sign in its name
2. try to build/tag the image

#### Expected behaviour

Replace hash sign with a dash or something else just like it happens for slashes.

### Logs

<details>
<summary>Logs here</summary>

```
2020-12-05T14:55:41.9591861Z ##[section]Starting: Request a runner to run this job
2020-12-05T14:55:42.5631247Z Can't find any online and idle self-hosted runner in current repository that matches the required labels: 'ubuntu-latest'
2020-12-05T14:55:42.5631555Z Can't find any online and idle self-hosted runner in current repository's account/organization that matches the required labels: 'ubuntu-latest'
2020-12-05T14:55:42.5631906Z Found online and idle hosted runner in current repository's account/organization that matches the required labels: 'ubuntu-latest'
2020-12-05T14:55:42.7639461Z ##[section]Finishing: Request a runner to run this job
2020-12-05T14:55:51.7446658Z Current runner version: '2.274.2'
2020-12-05T14:55:51.7482226Z ##[group]Operating System
2020-12-05T14:55:51.7483156Z Ubuntu
2020-12-05T14:55:51.7483604Z 18.04.5
2020-12-05T14:55:51.7483990Z LTS
2020-12-05T14:55:51.7484418Z ##[endgroup]
2020-12-05T14:55:51.7485078Z ##[group]Virtual Environment
2020-12-05T14:55:51.7486126Z Environment: ubuntu-18.04
2020-12-05T14:55:51.7486702Z Version: 20201129.1
2020-12-05T14:55:51.7487701Z Included Software: https://github.com/actions/virtual-environments/blob/ubuntu18/20201129.1/images/linux/Ubuntu1804-README.md
2020-12-05T14:55:51.7488743Z ##[endgroup]
2020-12-05T14:55:51.7492482Z Prepare workflow directory
2020-12-05T14:55:51.8170632Z Prepare all required actions
2020-12-05T14:55:51.8182592Z Getting action download info
2020-12-05T14:55:52.1582860Z Download action repository 'actions/checkout@v2'
2020-12-05T14:55:55.3407651Z Download action repository 'docker/setup-buildx-action@v1'
2020-12-05T14:55:56.9234187Z Download action repository 'crazy-max/ghaction-docker-meta@v1'
2020-12-05T14:55:58.6776711Z Download action repository 'actions/cache@v2'
2020-12-05T14:56:00.6388950Z Download action repository 'docker/login-action@v1'
2020-12-05T14:56:02.5685405Z Download action repository 'docker/build-push-action@v2'
2020-12-05T14:56:04.8856443Z ##[group]Run actions/checkout@v2
2020-12-05T14:56:04.8857069Z with:
2020-12-05T14:56:04.8858428Z   repository: Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:04.8860176Z   token: ***
2020-12-05T14:56:04.8860949Z   ssh-strict: true
2020-12-05T14:56:04.8861694Z   persist-credentials: true
2020-12-05T14:56:04.8862197Z   clean: true
2020-12-05T14:56:04.8862590Z   fetch-depth: 1
2020-12-05T14:56:04.8862987Z   lfs: false
2020-12-05T14:56:04.8863367Z   submodules: false
2020-12-05T14:56:04.8863915Z ##[endgroup]
2020-12-05T14:56:05.3118741Z Syncing repository: Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:05.3119841Z ##[group]Getting Git version info
2020-12-05T14:56:05.3121342Z Working directory is '/home/runner/work/SoftwareEngineering-WS2021-Gruppe1/SoftwareEngineering-WS2021-Gruppe1'
2020-12-05T14:56:05.3183878Z [command]/usr/bin/git version
2020-12-05T14:56:05.3355205Z git version 2.29.2
2020-12-05T14:56:05.3381330Z ##[endgroup]
2020-12-05T14:56:05.3394611Z Deleting the contents of '/home/runner/work/SoftwareEngineering-WS2021-Gruppe1/SoftwareEngineering-WS2021-Gruppe1'
2020-12-05T14:56:05.3397089Z ##[group]Initializing the repository
2020-12-05T14:56:05.3402389Z [command]/usr/bin/git init /home/runner/work/SoftwareEngineering-WS2021-Gruppe1/SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:05.3502295Z Initialized empty Git repository in /home/runner/work/SoftwareEngineering-WS2021-Gruppe1/SoftwareEngineering-WS2021-Gruppe1/.git/
2020-12-05T14:56:05.3518548Z [command]/usr/bin/git remote add origin https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:05.3568887Z ##[endgroup]
2020-12-05T14:56:05.3570827Z ##[group]Disabling automatic garbage collection
2020-12-05T14:56:05.3571833Z [command]/usr/bin/git config --local gc.auto 0
2020-12-05T14:56:05.3622327Z ##[endgroup]
2020-12-05T14:56:05.3625085Z ##[group]Setting up auth
2020-12-05T14:56:05.3626246Z [command]/usr/bin/git config --local --name-only --get-regexp core\.sshCommand
2020-12-05T14:56:05.3660680Z [command]/usr/bin/git submodule foreach --recursive git config --local --name-only --get-regexp 'core\.sshCommand' && git config --local --unset-all 'core.sshCommand' || :
2020-12-05T14:56:05.4106215Z [command]/usr/bin/git config --local --name-only --get-regexp http\.https\:\/\/github\.com\/\.extraheader
2020-12-05T14:56:05.4173166Z [command]/usr/bin/git submodule foreach --recursive git config --local --name-only --get-regexp 'http\.https\:\/\/github\.com\/\.extraheader' && git config --local --unset-all 'http.https://github.com/.extraheader' || :
2020-12-05T14:56:05.4436307Z [command]/usr/bin/git config --local http.https://github.com/.extraheader AUTHORIZATION: basic ***
2020-12-05T14:56:05.4495085Z ##[endgroup]
2020-12-05T14:56:05.4496568Z ##[group]Fetching the repository
2020-12-05T14:56:05.4506426Z [command]/usr/bin/git -c protocol.version=2 fetch --no-tags --prune --progress --no-recurse-submodules --depth=1 origin +a360c24101763da049cf68ada5731c19242c8c20:refs/remotes/origin/feature/#6-skillquiz
2020-12-05T14:56:06.1674797Z remote: Enumerating objects: 136, done.
2020-12-05T14:56:06.1677609Z remote: Counting objects:   0% (1/136)
2020-12-05T14:56:06.1689401Z remote: Counting objects:   1% (2/136)
2020-12-05T14:56:06.1690022Z remote: Counting objects:   2% (3/136)
...
2020-12-05T14:56:06.2153876Z remote: Counting objects:  98% (134/136)
2020-12-05T14:56:06.2154321Z remote: Counting objects:  99% (135/136)
2020-12-05T14:56:06.2154771Z remote: Counting objects: 100% (136/136)
2020-12-05T14:56:06.2155241Z remote: Counting objects: 100% (136/136), done.
2020-12-05T14:56:06.2156040Z remote: Compressing objects:   0% (1/120)
2020-12-05T14:56:06.2156552Z remote: Compressing objects:   1% (2/120)
....
2020-12-05T14:56:06.2207047Z remote: Compressing objects:  98% (118/120)
2020-12-05T14:56:06.2207771Z remote: Compressing objects:  99% (119/120)
2020-12-05T14:56:06.2208717Z remote: Compressing objects: 100% (120/120)
2020-12-05T14:56:06.2209303Z remote: Compressing objects: 100% (120/120), done.
2020-12-05T14:56:06.2321971Z Receiving objects:   0% (1/136)
2020-12-05T14:56:06.2322986Z Receiving objects:   1% (2/136)
2020-12-05T14:56:06.2323674Z Receiving objects:   2% (3/136)
....
2020-12-05T14:56:07.0171968Z Receiving objects:  98% (134/136), 6.45 MiB | 12.89 MiB/s
2020-12-05T14:56:07.0172571Z Receiving objects:  99% (135/136), 6.45 MiB | 12.89 MiB/s
2020-12-05T14:56:07.0173087Z Receiving objects: 100% (136/136), 6.45 MiB | 12.89 MiB/s
2020-12-05T14:56:07.0173738Z Receiving objects: 100% (136/136), 16.54 MiB | 21.12 MiB/s, done.
2020-12-05T14:56:07.0174644Z Resolving deltas:   0% (0/8)
2020-12-05T14:56:07.0175401Z Resolving deltas:  12% (1/8)
2020-12-05T14:56:07.0175946Z Resolving deltas:  25% (2/8)
2020-12-05T14:56:07.0176498Z Resolving deltas:  37% (3/8)
2020-12-05T14:56:07.0177093Z Resolving deltas:  50% (4/8)
2020-12-05T14:56:07.0177683Z Resolving deltas:  62% (5/8)
2020-12-05T14:56:07.0182550Z Resolving deltas:  75% (6/8)
2020-12-05T14:56:07.0197359Z Resolving deltas:  87% (7/8)
2020-12-05T14:56:07.0198417Z Resolving deltas: 100% (8/8)
2020-12-05T14:56:07.0199188Z Resolving deltas: 100% (8/8), done.
2020-12-05T14:56:07.2623477Z From https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:07.2625307Z  * [new ref]         a360c24101763da049cf68ada5731c19242c8c20 -> origin/feature/#6-skillquiz
2020-12-05T14:56:07.2653797Z ##[endgroup]
2020-12-05T14:56:07.2656401Z ##[group]Determining the checkout info
2020-12-05T14:56:07.2659002Z ##[endgroup]
2020-12-05T14:56:07.2661860Z ##[group]Checking out the ref
2020-12-05T14:56:07.2665986Z [command]/usr/bin/git checkout --progress --force -B feature/#6-skillquiz refs/remotes/origin/feature/#6-skillquiz
2020-12-05T14:56:07.4147785Z Switched to a new branch 'feature/#6-skillquiz'
2020-12-05T14:56:07.4151180Z Branch 'feature/#6-skillquiz' set up to track remote branch 'feature/#6-skillquiz' from 'origin'.
2020-12-05T14:56:07.4162870Z ##[endgroup]
2020-12-05T14:56:07.4229274Z [command]/usr/bin/git log -1 --format='%H'
2020-12-05T14:56:07.4262815Z 'a360c24101763da049cf68ada5731c19242c8c20'
2020-12-05T14:56:07.4424938Z ##[group]Run docker/setup-buildx-action@v1
2020-12-05T14:56:07.4425399Z with:
2020-12-05T14:56:07.4425768Z   driver: docker-container
2020-12-05T14:56:07.4426685Z   buildkitd-flags: --allow-insecure-entitlement security.insecure --allow-insecure-entitlement network.host
2020-12-05T14:56:07.4427580Z   install: false
2020-12-05T14:56:07.4427941Z   use: true
2020-12-05T14:56:07.4428247Z ##[endgroup]
2020-12-05T14:56:09.0470020Z 📣 Buildx version: 0.4.2
2020-12-05T14:56:09.3364761Z ##[group]🔨 Creating a new builder instance
2020-12-05T14:56:09.3418865Z [command]/usr/bin/docker buildx create --name builder-build-2 --driver docker-container --driver-opt image=moby/buildkit:v0.8-beta --buildkitd-flags --allow-insecure-entitlement security.insecure --allow-insecure-entitlement network.host --use
2020-12-05T14:56:09.4598324Z builder-build-2
2020-12-05T14:56:09.4636512Z ##[endgroup]
2020-12-05T14:56:09.4645205Z ##[group]🏃 Booting builder
2020-12-05T14:56:09.4740388Z [command]/usr/bin/docker buildx inspect --bootstrap
2020-12-05T14:56:09.5579688Z #1 [internal] booting buildkit
2020-12-05T14:56:09.7177264Z #1 pulling image moby/buildkit:v0.8-beta
2020-12-05T14:56:13.3099556Z #1 pulling image moby/buildkit:v0.8-beta 3.8s done
2020-12-05T14:56:13.4597282Z #1 creating container buildx_buildkit_builder-build-20
2020-12-05T14:56:15.9010829Z #1 creating container buildx_buildkit_builder-build-20 2.6s done
2020-12-05T14:56:15.9011542Z #1 DONE 6.3s
2020-12-05T14:56:16.0406864Z Name:   builder-build-2
2020-12-05T14:56:16.0432877Z Driver: docker-container
2020-12-05T14:56:16.0434533Z
2020-12-05T14:56:16.0434932Z Nodes:
2020-12-05T14:56:16.0435741Z Name:      builder-build-20
2020-12-05T14:56:16.0453786Z Endpoint:  unix:///var/run/docker.sock
2020-12-05T14:56:16.0454393Z Status:    running
2020-12-05T14:56:16.0455818Z Flags:     --allow-insecure-entitlement security.insecure --allow-insecure-entitlement network.host
2020-12-05T14:56:16.0456824Z Platforms: linux/amd64, linux/386
2020-12-05T14:56:16.0457713Z ##[endgroup]
2020-12-05T14:56:16.0458777Z ##[group]🛒 Extracting available platforms
2020-12-05T14:56:16.2705293Z linux/amd64,linux/386
2020-12-05T14:56:16.2708313Z ##[endgroup]
2020-12-05T14:56:16.2891859Z ##[group]Run crazy-max/ghaction-docker-meta@v1
2020-12-05T14:56:16.2892694Z with:
2020-12-05T14:56:16.2893623Z   images: Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1/skillmanagement-web
2020-12-05T14:56:16.2894576Z   tag-sha: true
2020-12-05T14:56:16.2895422Z   tag-edge: false
2020-12-05T14:56:16.2895838Z   tag-match-group: 0
2020-12-05T14:56:16.2896400Z   tag-latest: true
2020-12-05T14:56:16.2896807Z   tag-match-latest: true
2020-12-05T14:56:16.2897287Z   tag-schedule: nightly
2020-12-05T14:56:16.2898041Z   github-token: ***
2020-12-05T14:56:16.2898793Z ##[endgroup]
2020-12-05T14:56:17.2697042Z ##[group]Context info
2020-12-05T14:56:17.2697558Z eventName: workflow_dispatch
2020-12-05T14:56:17.2698131Z sha: a360c24101763da049cf68ada5731c19242c8c20
2020-12-05T14:56:17.2699403Z ref: refs/heads/feature/#6-skillquiz
2020-12-05T14:56:17.2700104Z workflow: skillmanagement-web-build
2020-12-05T14:56:17.2701902Z action: crazy-maxghaction-docker-meta
2020-12-05T14:56:17.2702726Z actor: whymatter
2020-12-05T14:56:17.2703101Z runNumber: 4
2020-12-05T14:56:17.2703408Z runId: 402669340
2020-12-05T14:56:17.2703880Z ##[endgroup]
2020-12-05T14:56:17.2705499Z ##[group]Docker image version
2020-12-05T14:56:17.2706573Z feature-#6-skillquiz
2020-12-05T14:56:17.2707091Z ##[endgroup]
2020-12-05T14:56:17.2739130Z ##[group]Docker tags
2020-12-05T14:56:17.2740377Z gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:feature-#6-skillquiz
2020-12-05T14:56:17.2742305Z gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:sha-a360c24
2020-12-05T14:56:17.2743233Z ##[endgroup]
2020-12-05T14:56:17.2745149Z ##[group]Docker labels
2020-12-05T14:56:17.2746238Z org.opencontainers.image.title=SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:17.2747350Z org.opencontainers.image.description=Gruppe 1 SE WS2021
2020-12-05T14:56:17.2748777Z org.opencontainers.image.url=https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:17.2750564Z org.opencontainers.image.source=https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
2020-12-05T14:56:17.2751979Z org.opencontainers.image.version=feature-#6-skillquiz
2020-12-05T14:56:17.2753039Z org.opencontainers.image.created=2020-12-05T14:56:17.269Z
2020-12-05T14:56:17.2753964Z org.opencontainers.image.revision=a360c24101763da049cf68ada5731c19242c8c20
2020-12-05T14:56:17.2754890Z org.opencontainers.image.licenses=
2020-12-05T14:56:17.2755460Z ##[endgroup]
2020-12-05T14:56:17.2930284Z ##[group]Run actions/cache@v2
2020-12-05T14:56:17.2930882Z with:
2020-12-05T14:56:17.2931233Z   path: /tmp/.buildx-cache
2020-12-05T14:56:17.2932579Z   key: Linux-buildx-a360c24101763da049cf68ada5731c19242c8c20
2020-12-05T14:56:17.2933442Z   restore-keys: Linux-buildx-

2020-12-05T14:56:17.2934038Z ##[endgroup]
2020-12-05T14:56:18.0770498Z Cache not found for input keys: Linux-buildx-a360c24101763da049cf68ada5731c19242c8c20, Linux-buildx-
2020-12-05T14:56:18.0905625Z ##[group]Run docker/login-action@v1
2020-12-05T14:56:18.0906276Z with:
2020-12-05T14:56:18.0906641Z   registry: ghcr.io
2020-12-05T14:56:18.0907086Z   username: whymatter
2020-12-05T14:56:18.0908142Z   password: ***
2020-12-05T14:56:18.0908491Z   logout: true
2020-12-05T14:56:18.0908819Z ##[endgroup]
2020-12-05T14:56:18.1377370Z 🔑 Logging into ghcr.io...
2020-12-05T14:56:19.1062368Z 🎉 Login Succeeded!
2020-12-05T14:56:19.1245938Z ##[group]Run docker/build-push-action@v2
2020-12-05T14:56:19.1246407Z with:
2020-12-05T14:56:19.1246802Z   context: ./skillmanagement/web
2020-12-05T14:56:19.1247299Z   file: ./build/Dockerfile
2020-12-05T14:56:19.1248886Z   tags: gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:feature-#6-skillquiz
gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:sha-a360c24
2020-12-05T14:56:19.1254544Z   labels: org.opencontainers.image.title=SoftwareEngineering-WS2021-Gruppe1
org.opencontainers.image.description=Gruppe 1 SE WS2021
org.opencontainers.image.url=https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
org.opencontainers.image.source=https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1
org.opencontainers.image.version=feature-#6-skillquiz
org.opencontainers.image.created=2020-12-05T14:56:17.269Z
org.opencontainers.image.revision=a360c24101763da049cf68ada5731c19242c8c20
org.opencontainers.image.licenses=
2020-12-05T14:56:19.1259582Z   push: true
2020-12-05T14:56:19.1260050Z   cache-from: type=local,src=/tmp/.buildx-cache
2020-12-05T14:56:19.1260672Z   cache-to: type=local,dest=/tmp/.buildx-cache
2020-12-05T14:56:19.1261867Z   pull: false
2020-12-05T14:56:19.1262237Z   no-cache: false
2020-12-05T14:56:19.1262552Z   load: false
2020-12-05T14:56:19.1263549Z   github-token: ***
2020-12-05T14:56:19.1263912Z ##[endgroup]
2020-12-05T14:56:19.4033108Z 📣 Buildx version: 0.4.2
2020-12-05T14:56:19.4088758Z 🏃 Starting build...
2020-12-05T14:56:19.4126951Z [command]/usr/bin/docker buildx build --label org.opencontainers.image.title=SoftwareEngineering-WS2021-Gruppe1 --label org.opencontainers.image.description=Gruppe 1 SE WS2021 --label org.opencontainers.image.url=https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1 --label org.opencontainers.image.source=https://github.com/Gruppe-1-SE-WS21/SoftwareEngineering-WS2021-Gruppe1 --label org.opencontainers.image.version=feature-#6-skillquiz --label org.opencontainers.image.created=2020-12-05T14:56:17.269Z --label org.opencontainers.image.revision=a360c24101763da049cf68ada5731c19242c8c20 --label org.opencontainers.image.licenses= --tag gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:feature-#6-skillquiz --tag gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:sha-a360c24 --iidfile /tmp/docker-build-push-PdRQy5/iidfile --cache-from type=local,src=/tmp/.buildx-cache --cache-to type=local,dest=/tmp/.buildx-cache --file ./build/Dockerfile --push ./skillmanagement/web
2020-12-05T14:56:19.5046482Z time="2020-12-05T14:56:19Z" level=warning msg="invalid non-bool value for BUILDX_NO_DEFAULT_LOAD: "
2020-12-05T14:56:19.5072209Z invalid tag "gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:feature-#6-skillquiz": invalid reference format
2020-12-05T14:56:19.5219242Z ##[error]buildx call failed with: invalid tag "gruppe-1-se-ws21/softwareengineering-ws2021-gruppe1/skillmanagement-web:feature-#6-skillquiz": invalid reference format
2020-12-05T14:56:19.5357187Z Post job cleanup.
2020-12-05T14:56:19.6256585Z 🚿 Removing temp folder /tmp/docker-build-push-PdRQy5
2020-12-05T14:56:19.6405926Z Post job cleanup.
2020-12-05T14:56:19.6980864Z [command]/usr/bin/docker logout ghcr.io
2020-12-05T14:56:19.7426134Z Removing login credentials for ghcr.io
2020-12-05T14:56:19.7568626Z Post job cleanup.
2020-12-05T14:56:19.8201428Z [command]/usr/bin/docker buildx rm builder-build-2
2020-12-05T14:56:20.1722934Z Post job cleanup.
2020-12-05T14:56:20.2875772Z [command]/usr/bin/git version
2020-12-05T14:56:20.2956681Z git version 2.29.2
2020-12-05T14:56:20.2996404Z [command]/usr/bin/git config --local --name-only --get-regexp core\.sshCommand
2020-12-05T14:56:20.3032810Z [command]/usr/bin/git submodule foreach --recursive git config --local --name-only --get-regexp 'core\.sshCommand' && git config --local --unset-all 'core.sshCommand' || :
2020-12-05T14:56:20.3369643Z [command]/usr/bin/git config --local --name-only --get-regexp http\.https\:\/\/github\.com\/\.extraheader
2020-12-05T14:56:20.3400391Z http.https://github.com/.extraheader
2020-12-05T14:56:20.3410951Z [command]/usr/bin/git config --local --unset-all http.https://github.com/.extraheader
2020-12-05T14:56:20.3462114Z [command]/usr/bin/git submodule foreach --recursive git config --local --name-only --get-regexp 'http\.https\:\/\/github\.com\/\.extraheader' && git config --local --unset-all 'http.https://github.com/.extraheader' || :
2020-12-05T14:56:20.3814916Z Cleaning up orphan processes
```
</details>

### Additional contract requirements

The `org.opencontainers.image.version` label is derived from the same branch-derived value as the Docker tag. When the branch name contains a hash sign, this label value must also have the hash sign replaced with a dash, exactly like the tag value. For example, a branch named `my/feature#1245` produces the version label `org.opencontainers.image.version=my-feature-1245`.
