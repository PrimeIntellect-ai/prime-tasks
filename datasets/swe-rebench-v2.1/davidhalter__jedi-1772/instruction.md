Jedi is unable to complete import statements for zip-modules
Jedi gives no completion for imports of modules that are zip files.

Example (there is a module mymodule.zip in `sys.path`):
```python
import jedi
print(jedi.Script('import mymo').complete())
```
Trying to complete `import <symbol> from mymodule` doesn't work either.

jedi version: 0.18.0

### Additional contract requirements

Jedi must offer import-path completions for modules and packages stored in zip files on `sys.path`, including partial top-level imports. In `from` imports, Jedi must also offer names provided by a module stored in a zip file.
