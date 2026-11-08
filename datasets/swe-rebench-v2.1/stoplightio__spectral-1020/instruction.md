Can't silence reports
**Describe the bug**

I just installed 5.2.0 with the new silencing feature introduced by @nulltoken. I'm trying to silence the errors I am getting for my openapi.yaml described here: #915

To start with broad example, I added
```
except:
  "openapi.yaml#":
    - oas3-valid-schema-example
    - oas3-valid-content-schema-example
```
Unfortunately, it still shows the errors. I also tried some more paths, but except for an error that the source is missing for path `#` nothing changed.

What I really want to achieve:
```
except:
  "openapi.yaml#/components/schemas/process_graph":
    - oas3-valid-schema-example
  "openapi.yaml#/paths/\/processes/get":
    - oas3-valid-content-schema-example
  "openapi.yaml#/paths/\/process_graphs/get":
    - oas3-valid-content-schema-example
  "openapi.yaml#/paths/\/service_types/get":
    - oas3-valid-content-schema-example
```
Although for this example I'm not sure whether the forward slashes are correctly escaped.

I'm using JSON Reference here because the example in the docs look like JSON Reference although the doc says JSON Path. I'm confused, but tried both...

**To Reproduce**

See #915 and add the code given above.

**Expected behavior**

Errors should be silent. Either I don't understand the new feature/docs and that needs improvement or there's a bug in the code.

**Environment (remove any that are not applicable):**
 - Library version: 5.2.0
 - OS: Windows 10
