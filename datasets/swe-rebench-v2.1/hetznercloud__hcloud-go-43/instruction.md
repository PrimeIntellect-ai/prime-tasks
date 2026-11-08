Implement changing a server’s type
https://docs.hetzner.cloud/#resources-server-actions-post-10

### Additional contract requirements

The server client must provide `ChangeType(ctx context.Context, server *Server, opts ServerChangeTypeOpts)` to request a server type change by posting to `/servers/{id}/actions/change_type`. `ServerChangeTypeOpts` must include `ServerType *ServerType`, identifying the target by its ID or name, and `UpgradeDisk bool`, indicating whether the disk should be upgraded. The operation returns the created `*Action`, the raw response, and an error when the request fails.
