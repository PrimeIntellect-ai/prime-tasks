oclif rejects empty string given for required argument
Do you want to request a *feature* or report a *bug*?
-----------------------------------------------------

Report a bug

What is the current behavior?
-----------------------------
oclif rejects an empty string argument when a string argument is requried

Example code:

```
import {Command, flags} from '@oclif/command'

class Foo extends Command {
  static description = 'describe the command here'

  static args = [{name: 'file', required: true}]

  async run() {
    const {args, flags} = this.parse(Foo)
  }
}

export = Foo
```

Example output:

```
$ ./bin/run
 ›   Error: Missing 1 required arg:
 ›   file
 ›   See more help with --help
$ ./bin/run ''
 ›   Error: Missing 1 required arg:
 ›   file
 ›   See more help with --help
$ ./bin/run 'foo'
$
```

The first error is expected (we omitted the argument). The second is not (we supplied an empty string as argument). In the 3rd case, the command succeeds as expected.

What is the expected behavior?
------------------------------
An empty string argument should be accepted.

I'm using oclif/command 1.8.0 on Ubuntu 20.04.
