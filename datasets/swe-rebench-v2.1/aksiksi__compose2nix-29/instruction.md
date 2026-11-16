serviceConfig Restart no with quoted strings
Hey, thanks for the great tool! With the following minimal `docker-compose.yml`
```
services:
  test:
    image: nginx:latest
```
and `compose2nix -project test` I get
```
  systemd.services."podman-test-test" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "\"no\"";
    };
  };
```
where nix complains about the [escaped quotes](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/systemd-unit-options.nix#L35) with something like this
```
       error: A definition for option `systemd.services.podman-test-test.serviceConfig' is not of type `attribute set of (systemd option)'. Definition values:
       - In `/nix/store/yv0aqwqsvns7rx164q6lvjgy1fpvfk0c-source/test.nix':
           {
             Restart = {
               _type = "override";
               content = "\"no\"";
               priority = 500;
           ...
```
please let me know if you would like to have a PR for that
