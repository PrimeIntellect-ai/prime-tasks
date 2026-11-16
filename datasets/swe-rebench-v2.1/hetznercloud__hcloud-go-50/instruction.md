Implement changing a SSH key’s name
https://docs.hetzner.cloud/#resources-ssh-keys-put

### Additional contract requirements

Expose the name-changing operation as `SSHKeyClient.Update`. It must accept `SSHKeyUpdateOpts`, which has a `Name string` field for the requested SSH key name.
