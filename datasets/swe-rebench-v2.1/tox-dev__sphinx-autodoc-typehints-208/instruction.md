OSError: source code not available when using Pydantic models
Firstly, thank you for this package and your maintenance of it.

In the latest releases, v1.15.0 and v1.15.1, I have noticed my documentation failing to build with an OSError.

The issue seems to be related to `sphinx-autodoc-typehints` and Pydantic models.

I have applied `<v1.15.0` as a version constraint as a workaround.

Here is the error trace.

```
[app] emitting event: 'builder-inited'()
building [mo]: targets for 0 po files that are out of date
[build target] did not in env: 'index'
building [html]: targets for 1 source files that are out of date
updating environment: [app] emitting event: 'env-get-outdated'(<sphinx.environment.BuildEnvironment object at 0x7fe9ae252070>, {'index'}, set(), set())
[new config] 1 added, 0 changed, 0 removed
[app] emitting event: 'env-before-read-docs'(<sphinx.environment.BuildEnvironment object at 0x7fe9ae252070>, ['index'])
reading sources... [100%] index
[app] emitting event: 'env-purge-doc'(<sphinx.environment.BuildEnvironment object at 0x7fe9ae252070>, 'index')
[app] emitting event: 'source-read'('index', [".. sphinx-autodoc-typehints-example documentation master file, created by\n   sphinx-qui
[autodoc] /Users/johnmuddle/workspace/sphinx-autodoc-typehints-example/docs/index.rst:13: input:
.. autoclass :: package.model.Website


[autodoc] from package.model import Website
[autodoc] import package.model => <module 'package.model' from '/Users/johnmuddle/workspace/sphinx-autodoc-typehints-example/package/model.py'>
[autodoc] getattr(_, 'Website')
[autodoc] => <class 'package.model.Website'>
[app] emitting event: 'autodoc-process-signature'('class', 'package.model.Website', <class 'package.model.Website'>, {'members': []}, '(*, name: str,
[app] emitting event: 'autodoc-process-docstring'('class', 'package.model.Website', <class 'package.model.Website'>, {'members': []}, ['Website model
[app] emitting event: 'build-finished'(ExtensionError("Handler <function process_docstring at 0x7fe9b1aeeca0> for event 'autodoc-process-d

Traceback (most recent call last):
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/events.py", line 101, in emit
    results.append(listener.handler(self.app, *args))
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx_autodoc_typehints/__init__.py", line 446, in process_docstring
    type_hints = get_all_type_hints(obj, name)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx_autodoc_typehints/__init__.py", line 263, in get_all_type_hints
    result = _get_type_hint(name, obj)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx_autodoc_typehints/__init__.py", line 291, in _get_type_hint
    _resolve_type_guarded_imports(obj)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx_autodoc_typehints/__init__.py", line 284, in _resolve_type_guarded_imports
    [HIDDEN]
  File "/Users/johnmuddle/miniconda3/lib/python3.9/inspect.py", line 1024, in getsource
    lines, lnum = getsourcelines(object)
  File "/Users/johnmuddle/miniconda3/lib/python3.9/inspect.py", line 1006, in getsourcelines
    lines, lnum = findsource(object)
  File "/Users/johnmuddle/miniconda3/lib/python3.9/inspect.py", line 827, in findsource
    raise OSError('source code not available')
OSError: source code not available

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/cmd/build.py", line 280, in build_main
    app.build(args.force_all, filenames)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/application.py", line 344, in build
    self.builder.build_update()
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/builders/__init__.py", line 294, in build_update
    self.build(to_build,
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/builders/__init__.py", line 308, in build
    updated_docnames = set(self.read())
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/builders/__init__.py", line 415, in read
    self._read_serial(docnames)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/builders/__init__.py", line 436, in _read_serial
    self.read_doc(docname)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/builders/__init__.py", line 476, in read_doc
    doctree = read_doc(self.app, self.env, self.env.doc2path(docname))
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/io.py", line 189, in read_doc
    pub.publish()
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/core.py", line 217, in publish
    self.document = self.reader.read(self.source, self.parser,
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/io.py", line 109, in read
    self.parse()
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/readers/__init__.py", line 78, in parse
    self.parser.parse(self.input, document)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/parsers.py", line 101, in parse
    self.statemachine.run(inputlines, document, inliner=self.inliner)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 170, in run
    results = StateMachineWS.run(self, input_lines, input_offset,
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/statemachine.py", line 239, in run
    context, next_state, result = self.check_line(
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/statemachine.py", line 451, in check_line
    return method(match, context, next_state)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 2769, in underline
    self.section(title, source, style, lineno - 1, messages)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 327, in section
    self.new_subsection(title, lineno, messages)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 393, in new_subsection
    newabsoffset = self.nested_parse(
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 281, in nested_parse
    state_machine.run(block, input_offset, memo=self.memo,
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 196, in run
    results = StateMachineWS.run(self, input_lines, input_offset)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/statemachine.py", line 239, in run
    context, next_state, result = self.check_line(
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/statemachine.py", line 451, in check_line
    return method(match, context, next_state)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 2344, in explicit_markup
    self.explicit_list(blank_finish)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 2369, in explicit_list
    newline_offset, blank_finish = self.nested_list_parse(
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 318, in nested_list_parse
    state_machine.run(block, input_offset, memo=self.memo,
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 196, in run
    results = StateMachineWS.run(self, input_lines, input_offset)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/statemachine.py", line 239, in run
    context, next_state, result = self.check_line(
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/statemachine.py", line 451, in check_line
    return method(match, context, next_state)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 2647, in explicit_markup
    nodelist, blank_finish = self.explicit_construct(match)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 2354, in explicit_construct
    return method(self, expmatch)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 2096, in directive
    return self.run_directive(
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/docutils/parsers/rst/states.py", line 2146, in run_directive
    result = directive_instance.run()
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/ext/autodoc/directive.py", line 162, in run
    documenter.generate(more_content=self.content)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/ext/autodoc/__init__.py", line 1774, in generate
    return super().generate(more_content=more_content,
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/ext/autodoc/__init__.py", line 981, in generate
    self.add_content(more_content)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/ext/autodoc/__init__.py", line 1760, in add_content
    super().add_content(more_content)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/ext/autodoc/__init__.py", line 636, in add_content
    for i, line in enumerate(self.process_doc(docstrings)):
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/ext/autodoc/__init__.py", line 577, in process_doc
    self.env.app.emit('autodoc-process-docstring',
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/application.py", line 454, in emit
    return self.events.emit(event, *args, allowed_exceptions=allowed_exceptions)
  File "/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/sphinx/events.py", line 109, in emit
    raise ExtensionError(__("Handler %r for event %r threw an exception") %
sphinx.errors.ExtensionError: Handler <function process_docstring at 0x7fe9b1aeeca0> for event 'autodoc-process-docstring' threw an exception (exception: source code not available)

Extension error (sphinx_autodoc_typehints):
Handler <function process_docstring at 0x7fe9b1aeeca0> for event 'autodoc-process-docstring' threw an exception (exception: source code not available)
make: *** [html] Error 2
```

[HIDDEN] Using a debugger, I was able to determine that `module` has the value `<module 'pydantic.main' from '/Users/johnmuddle/Library/Caches/pypoetry/virtualenvs/sphinx-autodoc-typehints-example-kGk3dAKY-py3.9/lib/python3.9/site-packages/pydantic/main.cpython-37m-x86_64-linux-gnu.so'>`

To help debug, I have an example https://github.com/jcmuddle/sphinx-autodoc-typehints-example
The `master` branch shows the docs failing to build when using `autoclass::`.
The `autodoc-pydantic` branch shows the docs failing to build when using `autopydantic_model::`. This example is closer to my use case but less general.

### Additional contract requirements

- Processing type hints while documenting a Pydantic model must not fail with an `OSError` solely because a dependency module has no source code available.
