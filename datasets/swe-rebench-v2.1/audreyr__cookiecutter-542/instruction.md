Choice prompts are disabled if there's a ~/.cookiecutterrc
Seems I don't get the nice prompts from https://github.com/audreyr/cookiecutter/pull/455 if I have a `~/.cookiecutterrc`

### Additional contract requirements

When a user configuration supplies a value that is one of a template choice variable's options, keep the variable as a choice prompt and make that configured option the prompt's default.
