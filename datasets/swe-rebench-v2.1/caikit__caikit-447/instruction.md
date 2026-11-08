Backend modules don't participate in service generation
## Describe the bug

A backend module (e.g. https://github.com/caikit/caikit-nlp/blob/0f14b486ef7840cef5a39863523c75ab06e7a650/caikit_nlp/modules/text_generation/text_generation_tgis.py#L45) may have a `base_module` with a `task`, and may define `@taskmethods`, but the parameteres from those task methods don't make it into the generated runtime services.

The root of the problem is that service generation only looks at plain modules, and not backend modules.

## Platform

Please provide details about the environment you are using, including the following:

- Interpreter version:
- Library version:

## Sample Code

Dump the services out for `caikit_nlp` and see that there is no `preserve_input_text` parameter anywhere.

## Expected behavior

The text gen interfaces should include `preserve_input_text`

## Observed behavior


## Additional context

### Additional contract requirements

- Parameters that a backend module's task method accepts must appear in the request messages of the generated runtime inference service, the same way parameters from regular modules do. For example, a text-generation backend's task method that accepts a `preserve_input_text` parameter must expose `preserve_input_text` in the generated text-generation interfaces.
