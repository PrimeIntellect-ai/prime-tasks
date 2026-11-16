Add ability to display stacktraces from unhandled exceptions
**Is your feature request related to a problem? Please describe.**
When the code inside of a command throws an exception that is not caught caporal prints the message of the exception that is thrown and has the process exit with code 2.  When this thrown exception is the result of bad inputs or failures to access resources (e.g. internet, files, etc), this behavior is OK.  However, when an exception is thrown because of poor programming logic on the part of the command author, it's very difficult to diagnose what has happened, expectially when the exception is thrown by dependency libraries or node built-ins.  It would be nice if there was some way that the stack trace could be rendered to fix those cases.

**Describe the solution you'd like**
When the verbose flag is set and an unhandled exception is thrown from inside a command, print out the full stack trace of the exception in addition to the exception's message.  When the verbose flag is not set, continue to only print out the exception's message.

**Describe alternatives you've considered**
Adding another flag or environment variable to toggle this behavior is an option, but extending existing flags is probably more desirable.

**Additional context**
The documentation so far doesn't really lay out best practices for errors and exceptions.

**Would you be able to work on it and provide a pull request ?**

- [x] Yes

### Additional contract requirements

Handling an unhandled command exception preserves process exit code 2, whether the command throws synchronously or returns a rejected promise.
