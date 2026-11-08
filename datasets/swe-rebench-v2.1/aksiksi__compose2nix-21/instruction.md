Should compose2nix reconsider relative volumes mounts from cwd?
Hi!

`compose2nix` really is awesome, and exceeds all of my expectations!

As I’m migrating a bunch of Docker Compose definitions, I was wondering if it would be wise to add an option to the parser to handle relative volume mountpoints more effectively.

It would leverage the issue where a `docker-compose.yml` contains a bunch of relative mountpoints from the current working directory.

### Current behavior

Currently, with the following definition:

```yaml
services:
   foo:
      image: bar
      volumes:
        - ./baz:/baz
```

Using `compose2nix -project fo`, the following Nix definition is generated:

```nix
{
  # …
  # Containers
  virtualisation.oci-containers.containers."foo-foo" = {
    image = "bar";
    volumes = [
      "baz:/baz:rw" # <---
    ];
    # …
  };
  # …
}
```

### Expected

Instead, I’d expect either a warning or the following output:

```nix
    volumes = [
      "/some/cwd/from/compose2nix/baz:/baz:rw"
    ];
```

## Propositions

I considered those 2 options:
1. Re-use the current working directory during `compose2nix` call (fastest but dumbest, and might break things if `docker-compose` wasn’t meant to be called from the same place `compose2nix` have been)
2. Add a flag to prefix the relative volume paths by the given directory (smartest, but requires checking help and yet another mandatory flag)

In any way, by default, I believe we should not let `compose2nix` trim the `./` prefix from relative volume mountpoints. We might want to consider issuing a warning instead (as it is done using `-check_systemd_mounts`)
