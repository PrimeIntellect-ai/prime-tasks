Print each "step"?
(This is with Knope 0.16.0; let me know if newer versions have changed this.)

I have a Knope that manually pushes tags, and it appears that the tag-pushing is failing. The failure itself is probably related to permissions rather than to Knope, but I don't see any output in the logs indicating what is happening. I think it would be helpful if, in addition to printing the output from each command-step, Knope could print the actual command about to be run.

Here's my release workflow:

<details>

```toml
[[workflows]]
name = "release"

[[workflows.steps]]
type = "Command"
# Knope feature request to make this behavior automatic:
# https://github.com/knope-dev/knope/issues/162
command = "cargo update -w --manifest-path rust/Cargo.toml"

[[workflows.steps]]
type = "Command"
command = " git add rust/Cargo.lock"

[[workflows.steps]]
type = "Command"
command = "git commit -m \"chore: prepare release $version\""

[workflows.steps.variables]
# `Version` is a "magic" Knope string that will be replaced with the actual version
"$version" = "Version"

[[workflows.steps]]
type = "Release"

# Needed because Knope doesn't have built-in GitLab support
[[workflows.steps]]
type = "Command"
command = "git push --push-option ci.skip"

[[workflows.steps]]
type = "Command"
command = "git push --tags --push-option ci.skip"

[[workflows.steps]]
type = "Command"
# See https://docs.gitlab.com/ee/user/project/releases/release_cli.html
command = "release-cli create --name \"Release $version\" --tag-name \"v$version\" --ref \"v$version\""
```
</details>

And here's Knope's output from the failed release:

<details>

```
$ knope release --verbose $KNOPE_FLAGS
    Updating crates.io index
     Locking 1 package to latest compatible version
    Updating rigetti-service-model v1.24.0 (/builds/rigetti/share/service-model/rust) -> v1.25.0
note: pass `--verbose` to see 95 unchanged dependencies behind latest
Looking for Git tags matching package name.
Finding version for python-grpc/pyproject.toml
Found 1.25.0 from file python-grpc/pyproject.toml
Finding version for python-grpc-betterproto/pyproject.toml
Found 1.25.0 from file python-grpc-betterproto/pyproject.toml
Finding version for rust/Cargo.toml
Found 1.25.0 from file rust/Cargo.toml
Finding version for golang/go.mod
Found 1.25.0 from file golang/go.mod
[main 945ef19] chore: prepare release 1.25.0
 1 file changed, 1 insertion(+), 1 deletion(-)
Finding version for python-grpc/pyproject.toml
Found 1.25.0 from file python-grpc/pyproject.toml
Finding version for python-grpc-betterproto/pyproject.toml
Found 1.25.0 from file python-grpc-betterproto/pyproject.toml
Finding version for rust/Cargo.toml
Found 1.25.0 from file rust/Cargo.toml
Finding version for golang/go.mod
Found 1.25.0 from file golang/go.mod
Searching for last package tag to determine if there's a release to release
warning: redirecting to https://gitlab.com/rigetti/share/service-model.git/
To https://gitlab.com/rigetti/share/service-model
   a61059e..945ef19  main -> main
warning: redirecting to https://gitlab.com/rigetti/share/service-model.git/
Everything up-to-date
Looking for Git tags matching package name.
Finding version for python-grpc/pyproject.toml
Found 1.25.0 from file python-grpc/pyproject.toml
Finding version for python-grpc-betterproto/pyproject.toml
Found 1.25.0 from file python-grpc-betterproto/pyproject.toml
Finding version for rust/Cargo.toml
Found 1.25.0 from file rust/Cargo.toml
Finding version for golang/go.mod
Found 1.25.0 from file golang/go.mod
time="2024-12-12T00:43:50Z" level=info msg="Creating Release..." catalog-publish=false cli=release-cli command=create name="Release 1.25.0" project-id=47478763 ref=v1.25.0 server-url="https://gitlab.com/" tag-message= tag-name=v1.25.0 version=0.20.0
time="2024-12-12T00:43:50Z" level=fatal msg="run app" cli=release-cli error="failed to create release: API Error Response status_code: 400 message: Target v1.25.0 is invalid" version=0.20.0
```

</details>

In particular, I'm not sure what the `Looking for Git tags matching package name` part is from, since I would expect that to be part of the `Release` step; and it looks like it does that _twice_, once before a `git push` (which is working) and once after. None of the output appears related to the `git push --tags`.

### Additional contract requirements

When the `--verbose` flag is set, Knope prints each workflow step before it runs. The printed line is `Running step ` followed by the step's debug representation; for a `Command` step this includes the command that is about to be run.
