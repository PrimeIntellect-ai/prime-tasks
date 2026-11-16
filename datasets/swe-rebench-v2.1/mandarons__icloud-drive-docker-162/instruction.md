[FEATURE] Override config path via environment variable ENV_CONFIG_FILE_PATH
**Use case**
In my setup icloud-drive-docker is created by a docker-compose file. I use a large chain of tools to control my environment, so I have a project in my private gitlab, which will setup the container from the docker-compose file via gitlab-runner on my qnap. In this workflow, the config will copied into the container and everything is fine and running.

In this environment, I am running watchtower to update the container if there is a new version. This is working too, but watchtower is not aware that with every container updated the config needs to be placed in the container.

If the config were in a separate folder from the source I could bind a volume and it would be persistent.

**Describe the solution you'd like**
Please add an environment variable for DEFAULT_CONFIG_FILE_PATH  like ENV_ICLOUD_PASSWORD_KEY. then I could place the Config file in a save place.

### Additional contract requirements

When `ENV_CONFIG_FILE_PATH` is set, the running application must load its configuration from that path. When the variable is unset, the existing default configuration path must remain usable.
