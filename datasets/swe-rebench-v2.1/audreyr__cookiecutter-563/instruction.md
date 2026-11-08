Improve help access and prompts from the CLI
A new user might enter any of the following and expect to be guided to the Help information about using the CLI:
- `cookiecutter`
- `cookiecutter -h`
- `cookiecutter --h`
- `cookiecutter help`

It would be helpful to improve the CLI messages or handle some of the additional cases for a new user.

@audreyr Thanks for the handy tool :bouquet:

<img width="773" alt="screen shot 2015-08-07 at 7 54 57 am" src="https://cloud.githubusercontent.com/assets/2680980/9138629/e64cb42a-3cd9-11e5-8c9c-cb9d726bd1eb.png">

### Additional contract requirements

- The CLI must accept `-h`, `--help`, and `help` as help entry points. For each of these, it exits with status 0 and prints help text that begins with `Usage`.
- Running the CLI with no template argument, or with the unrecognized option `--h`, must guide the user to the help information.
