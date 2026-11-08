Question about agenix encrypted env files
Hello!

I'm trying to follow your instructions for adding age encrypted env files.

I've created a file with in the format of a .env file and encrypted it with agenix in my flake dir.

Then I run `compose2nix -output default.nix --env_files=/run/agenix/tailscale-keys.env --include_env_files=true`
and I get this error: ` failed to open file /run/agenix/tailscale-keys.env: open /run/agenix/tailscale-keys.env: no such file or directory`. Referencing the path to the encrypted file make no sense either.

I'm guessing that nix needs to have a reference to that age file for it to be in the store and mounted under `/run/agenix`, however , I'm running `compose2nix` on another machine from the one running the container, and that "build machine" has no config to reference and mount the secret. Chicken-and-egg methinks.

I'm guessing that you could blindly reference the path to /run/agenix env file in the resulting .nix file, but not sure.

Ideas on how to proceed?

### Additional contract requirements

Provide a supported way to generate configuration when an env-file path supplied with `-env_files` does not exist on the machine running compose2nix. The `-ignore_missing_env_files=true` option must allow conversion to proceed without that file, rather than failing solely because it cannot be opened.
