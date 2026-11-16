Update CLI provider to point to the shipped Runme CLI
Currently we have a CLI button for every code block that is suppose to use the Runme CLI to execute the command inside:

![cli](https://user-images.githubusercontent.com/731337/224189757-28cf1108-4e08-4daf-8454-58a7b14c9246.gif)

The button is using the `CliProvider` class which checks whether the CLI is installed to run the action. Now that we have the CLI shipped as part of the extension we can just point directly to it.

@sourishkrout happy to take a stab at this if you think this make sense.

### Additional contract requirements

- For a cell named `foo-bar` in `/foo/bar/README.md`, when the executable path is `/bin/runme`, send this exact terminal command, without quoting the executable path: `/bin/runme run foo-bar --chdir="/foo/bar" --filename="README.md"`.
