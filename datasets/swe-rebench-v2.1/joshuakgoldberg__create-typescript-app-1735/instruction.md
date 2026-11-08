📝 Documentation: Streamline VS Code debugging mentions in .github/DEVELOPMENT.md
### Bug Report Checklist

- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Following #1290 and split out of #1670: there are a few places that debugging with VS Code is mentioned now:

* _Testing_ > _Debugging Tests_
* _Debugging_:
  * _Unit Tests_
  * _`bin` Apps_

I'm now realizing there's a bit of duplication there for testing. I'll go ahead and dedup so that debugging is mentioned in the individual sections, rather than its own.

### Additional Info

Filing this as a docs issue because it's not really a "bug", more of a cleanup. Even though it's going to produce a different output and should arguably be sent in as a `feat: ...` or `fix: ...`.

### Additional contract requirements

The generated `.github/DEVELOPMENT.md` must mention VS Code debugging in the individual sections rather than in a separate `## Debugging` section:

- The `## Testing` section includes a `### Debugging Tests` subsection.
- When the project has a `bin` entry, the `## Building` section includes a `### Built App Debugging` subsection.
- The generated document does not contain a separate `## Debugging` section.
