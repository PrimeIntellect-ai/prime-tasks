cropping leading whitespace in new version ??
i have an npx business card that's built on boxen.  When i use boxen@5.0.1 it displays leading whitespace in the strings, for example:

npx eswat2@2.2.110

However, if i build with the latest version (boxen@5.1.1), it displays without any leading whitespace:

npx eswat2@2.1.108

Has anyone else notice this problem ??

### Additional contract requirements

- Leading whitespace in the input text must be preserved in the rendered output. For example, `boxen('   foo')` must keep the three leading spaces before `foo`, and every line of a multi-line input must keep its own leading whitespace.
