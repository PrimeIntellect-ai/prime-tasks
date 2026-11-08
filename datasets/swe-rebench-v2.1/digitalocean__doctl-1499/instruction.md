create droplet in a specific project
digitalocean can group droplets into "projects".

"doctl compute droplet create" will create droplets into the default project.

how can I create a droplet in a specific project?

### Additional contract requirements

The `doctl compute droplet create` command accepts an optional `--project-id` UUID. When provided, the newly created Droplet is assigned to that project instead of remaining in the default project.
