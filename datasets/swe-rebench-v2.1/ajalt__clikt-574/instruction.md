Argfiles not supported in Clikt library version 5.0 or higher
The implementation of argument files (argfiles) fails when using Clikt library version 5.0 or higher. The application throws an error:
got unexpected extra argument (@src/test/resources/cliargs.arg)

This issue occurs when trying to parse arguments from a file. The feature works correctly with Clikt versions below 5.0. The bug can be reproduced easily by switching to Clikt version 5.0 or higher and making a minor adjustment to the import statement.

Steps to Reproduce:
1. Use Clikt library version 5.0 or higher.
2. Provide an argument file (e.g., @src/test/resources/cliargs.arg).
3. Update the import statement if necessary to match Clikt 5.0 syntax.
4. Run the application.

Expected Behavior:
The argument file should be parsed correctly, as it works with Clikt versions below 5.0.

Actual Behavior:
The application throws an error indicating an unexpected extra argument.

Environment:
- Clikt version: 5.0 or higher
- Operating System: [Specify OS]
- Java/Kotlin version: [Specify version if relevant]

Documentation: https://ajalt.github.io/clikt/advanced/#command-line-argument-files-argfiles

Attachments:
- Zip file containing relevant test cases and configurations: [CliktArgfiles.zip](https://github.com/user-attachments/files/18505787/CliktArgfiles.zip)

### Additional contract requirements

Argument files supplied as command-line input must be parsed at the root command as well as after a subcommand.
