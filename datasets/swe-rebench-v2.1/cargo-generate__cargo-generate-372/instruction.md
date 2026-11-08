Git SSH URL Support
The [Github Docs](https://docs.github.com/en/enterprise-server@3.0/github/getting-started-with-github/about-remote-repositories#about-remote-repositories) specify that a remote repository URL must have one of the following forms

- https://[hostname]/user/repo.git
- git@[hostname]:user/repo.git

As a result, if cargo-generate handles the former, I would expect it to handle the latter.

```
cameron@chowder ~> cargo generate --version
cargo-generate 0.6.1
cameron@chowder ~> cargo generate --git https://github.com/rustwasm/wasm-pack-template.git --name my-project
🔧   Creating project called `my-project`...
     Running `git fetch --force --update-head-ok 'https://github.com/rustwasm/wasm-pack-template.git' 'refs/heads/master:refs/remotes/origin/master'`
✨   Done! New project created /home/cameron/my-project
cameron@chowder ~> cargo generate --git git@github.com/rustwasm/wasm-pack-template.git --name my-project-2
🔧   Creating project called `my-project-2`...
Error: ⛔   Git Error: unexpected http status code: 404; class=Http (34)
cameron@chowder ~ [1]> cargo generate --git ssh://git@github.com/rustwasm/wasm-pack-template.git --name my-project-2
🔧   Creating project called `my-project-2`...
Error: ⛔   Git Error: authentication required but no callback set; class=Ssh (23)
```

If this is a features maintainers would like to have, then I would be happy to implement it.
