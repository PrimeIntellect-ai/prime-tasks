Implement enabling and disabling backups for a server
https://docs.hetzner.cloud/#resources-server-actions-post-11

https://docs.hetzner.cloud/#resources-server-actions-post-12

### Additional contract requirements

Expose enabling as `ServerClient.EnableBackup`, taking a server and a backup-window string; an empty string allows the API to choose a window. Expose disabling as `ServerClient.DisableBackup`, taking a server.
