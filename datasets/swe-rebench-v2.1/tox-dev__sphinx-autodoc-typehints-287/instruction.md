Property :rtype: is redundant
Looking at the output, it seems that properties have redundant types. In the test suite, `a_property` is an example. Defined like:
```py
@property
def a_property(self) -> str:
    """
    Property docstring
    """
```
The test suite asserts that the type of the property is included in two places. This strikes me as redundant and slightly confusing: does a property really "return" a value? In my opinion, the abstraction makes it look like we are "accessing" the value rather than returning it. To be specific, I want the following change in the output.
```patch
     property a_property: str

        Property docstring

-       Return type:
-          "str"
-
```
I applied the following patch to do this:
```patch
--- a/src/sphinx_autodoc_typehints/__init__.py
+++ b/src/sphinx_autodoc_typehints/__init__.py
@@ -611,7 +611,7 @@ def _inject_types_to_docstring(

                 lines.insert(insert_index, type_annotation)

-    if "return" in type_hints and not inspect.isclass(original_obj):
+    [HIDDEN]
         if what == "method" and name.endswith(".__init__"):  # avoid adding a return type for data class __init__
             return
         formatted_annotation = format_annotation(type_hints["return"], app.config)

 ```
Do people prefer the current behavior? If some people want the redundant property types, could we add a config option to opt out of it?
