v3.15 w/ Node 14+ crashes consistently when postBuild hook throws
Discovered during some investigative work by @dfreeman over here https://github.com/typed-ember/ember-cli-typescript/issues/1439#issuecomment-878244006

tldr:
 - postBuild returns a rejected promise, ember-cli crashes
 - rejected promises need to be caught from postBuild
