Load of module and client extremely slow.
## Description

I have a fairly complex GraphQL repository running on Hasura, that might have hundreds if not thousands of types and definitions. Right now I implemented this library for some specific queries and use cases, and all of those types available in the server are not needed for the execution of my isolated use case.

The generated code, creates a `__init__.py` file where everything is imported on package load. This `__init__.py` file is easily 4k lines of code, generating thousands of imports. Loading the `client` module might easily take minutes and GBs of RAM due to this reason. So I went ahead and deleted everything from the `__init__.py` and left it empty, as the calls to the right types happen on a module by module basis. This reduced my loading time from minutes to miliseconds, and the application still works as expected.

Now the question: is there a reason to import absolutely everything on the `__init__.py`?  For big and complex schemas is an overkill, and increases the application loading time by minutes. Should this file be empty and do a module by module import? - if that is the case, is this not already happening in the current implementation?

Maybe I am missing something, and I greatly appreciate your time and consideration.

### Additional contract requirements

A supported generated-client plugin, `NoReimportsPlugin` from `ariadne_codegen.contrib.no_reimports`, provides a `generate_init_module` hook. When used for client generation, the hook returns an AST module whose body is empty, preventing package initialization from eagerly importing generated modules. Generated client submodules remain individually importable and usable when the package initializer is empty.
