--add-package should fail when directory does not exists.
I have this tox env

```
[testenv:apidocs]
description = Build only the API documentation

commands =
    pydoctor \
    --add-package=bla_pydoctor \
    --project-name=pydoctor \
    --project-url=https://github.com/twisted/pydoctor/ \
    --html-viewsource-base=https://github.com/twisted/pydoctor/tree/master \
    --html-output=build/apidocs \
    --project-base-dir="{toxinidir}" \
    --docformat=epytext \
    --intersphinx=https://docs.python.org/3/objects.inv \
    --make-html
```

And it reporting that all is ok **adding module /home/adi/chevah/pydoctor/bla_pydoctor**

```
$ tox -e apidocs

adding module /home/adi/chevah/pydoctor/bla_pydoctor
writing html to build/apidocs using pydoctor.templatewriter.writer.TemplateWriter
starting ModuleIndexPage ...took 0.000845s
starting ClassIndexPage ...took 0.000718s
starting IndexPage ...took 0.001189s
starting NameIndexPage ...took 0.000789s
starting UndocumentedSummaryPage ...took 0.000718s
Generating objects inventory at build/apidocs/objects.inv
___________________________________ summary ____________________________________
  apidocs: commands succeeded
  congratulations :)
```

### Additional contract requirements

- When invoked without any source paths, the error output must include `No source paths given`.
