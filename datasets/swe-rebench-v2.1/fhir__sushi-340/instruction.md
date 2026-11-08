Generated jekyll comments interfere w/ IG Publisher parsing
SUSHI 0.11.2 introduced generated comments on SUSHI generated and copied files.  For xml files in pagecontent, we added Jekyll comments at the top of `.md` and `.xml` files.  While this works fine for `.md` files, the IG Publisher chokes on it for `.xml` files.

First it reports this error:
```
Error on line 1 column 1
  SXXP0003: Error reported by XML parser: Content is not allowed in prolog.
Exception generating page /Users/cmoesel/dev/fsh/simple-ig/build/temp/pages/_includes/index.xml: org.xml.sax.SAXParseException; lineNumber: 1; columnNumber: 1; Content is not allowed in prolog. (00:19.0789)
```

Then later on:
```
Jekyll has failed. Complete output from running Jekyll:   Liquid Exception: Could not locate the included file 'index.xml' in any of ["/Users/cmoesel/dev/fsh/simple-ig/build/temp/pages/_includes"]. Ensure it exists in one of those directories and, if it is a symlink, does not point outside your site source (00:23.0360)
Note: Check that Jekyll is installed correctly                                   (00:23.0360)
Publishing Content Failed: Process exited with an error: 1 (Exit value: 1)       (00:23.0361)
                                                                                 (00:23.0361)
Use -? to get command line help                                                  (00:23.0361)
                                                                                 (00:23.0361)
Stack Dump (for debugging):                                                      (00:23.0361)
org.apache.commons.exec.ExecuteException: Process exited with an error: 1 (Exit value: 1)
	at org.apache.commons.exec.DefaultExecutor.executeInternal(DefaultExecutor.java:404)
```

Thanks to Bob Milius for reporting this on Zulip: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/SUSHI.200.2E11.2E2/near/192873136

### Additional contract requirements

- For `.md` and `.xml` files that receive SUSHI warning comments, the opening line must include the output filename in the form `<!-- <filename> {% comment %}`; for example, `<!-- index.md {% comment %}` and `<!-- index.xml {% comment %}`.
