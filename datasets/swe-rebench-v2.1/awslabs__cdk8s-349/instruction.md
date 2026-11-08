Octal numbers are not parsed correctly when including manifests (or helm charts)
### Description of the bug:
<!--description of the bug:-->

See https://github.com/eemeli/yaml/issues/205




### Reproduction Steps:
<!--minimal amount of code that causes the bug (if possible) or a reference:-->

Try to `Include` a manifest that includes an octal number:

```yaml
my_number: 0666
```

The expectation is that this will be represented as:

```json
{ "my_number": 438 }
```

But instead, it is represented as `666`, which is not correct.

Root cause is an issue in the YAML library we use: https://github.com/eemeli/yaml/issues/205



### Error Log:
<!--what is the error message you are seeing?-->




### Environment:


  - **Framework Version**:
  - **OS**:


### Other:
<!-- e.g. detailed explanation, stacktraces, related issues, suggestions on how to fix, links for us to have context, eg. associated pull-request, stackoverflow, gitter, etc -->




---

This is :bug: Bug Report

### Additional contract requirements

- An included YAML manifest containing the scalar `0666` must be represented as the integer `438`.
- Octal values in the output of a Helm chart that is included must follow the same base-eight interpretation: `0666` must be represented as the integer `438`.
