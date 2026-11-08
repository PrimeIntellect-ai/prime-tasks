Paths are not reported correctly after multiple recursions of resolution
**Describe the bug**

It appears that the path of an error is reported correctly if resolve goes through a single `$ref` resolution, but not if it goes through more than one.

**To Reproduce**

Given this set of schemas:

<details>
<summary>Example grandparent, parent, and child schemas</summary>

```yaml
openapi: 3.0.3
components:
  schemas:
    Grandparent:
      type: object
      description: Grandparent resource
      properties:
        child:
          $ref: '#/components/schemas/Parent'
    Parent:
      type: object
      description: Parent resource
      properties:
        child:
          $ref: '#/components/schemas/Child'
    Child:
      type: object
      properties:
        name:
          type: string
          description: Name for a child
```
</details>

...only the `Child` schema violates this rule:

```yaml
rules:
  object-schema-description-defined:
    description: Object schemas must have a description
    severity: error
    formats: [oas3]
    given: $.components.schemas..[?(@.type == 'object')]
    then:
      field: description
      function: truthy
```

...but Spectral reports a violation in redundant locations:

```bash
$ spectral lint dedup.yaml

/experiments/dedup.yaml
 14:15  error  object-schema-description-defined  Object schemas must have a description  components.schemas.Parent.properties.child
 16:11  error  object-schema-description-defined  Object schemas must have a description  components.schemas.Child

✖ 2 problems (2 errors, 0 warnings, 0 infos, 0 hints)
```

This doesn't happen if the `Grandparent` schema doesn't exist, so it seems to be an artifact of Spectral looking "through" the `Grandparent` schema. The result makes _sense_ to me in that if `components.schemas.Parent.properties.child` is "resolved" then it's the location of a second error.

But things get even stranger if I add a `GreatGrandparent`:

<details>
  <summary>Example schemas with <b>great grandparent</b></summary>

```yaml
openapi: 3.0.3
components:
  schemas:
    GreatGrandparent:
      type: object
      description: Great grandparent resource
      properties:
        child:
          $ref: '#/components/schemas/Grandparent'
    Grandparent:
      type: object
      description: Grandparent resource
      properties:
        child:
          $ref: '#/components/schemas/Parent'
    Parent:
      type: object
      description: Parent resource
      properties:
        child:
          $ref: '#/components/schemas/Child'
    Child:
      type: object
      properties:
        name:
          type: string
          description: Name for a child
```
</details>

Now the same Spectral rule reports three errors:

```bash
$ spectral lint dedup.yaml

/experiments/dedup.yaml
 14:15  error  object-schema-description-defined  Object schemas must have a description  components.schemas.Grandparent.properties.child
 20:15  error  object-schema-description-defined  Object schemas must have a description  components.schemas.Parent.properties.child
 22:11  error  object-schema-description-defined  Object schemas must have a description  components.schemas.Child

✖ 3 problems (3 errors, 0 warnings, 0 infos, 0 hints)
```

The error at `components.schemas.Grandparent.properties.child` seems to exist because of the presence of the `GreatGrandparent` schema, but it doesn't really make sense to me at all, because even if one fully "resolved" the schema, there wouldn't be an error at that location. Rather, there would be one at "`components.schemas.Grandparent.properties.child.properties.child`", I think.

In any case, it seems like Spectral isn't able to keep track of the "real" path of an error as it recurses through a resolved document.

**Expected behavior**

Any number of errors caused by the same problem in the same place should report the same path.

**Environment (remove any that are not applicable):**
 - Library version: `spectral --version` reports `6.2.0`
 - OS: macOS 12.1 Monterey

Problem in paths reported for rule violations involving schema references within oneOf
**Describe the bug**
The spectral-core code related to mapping "resolved" paths to "unresolved" paths appears to get tripped up when dealing with schema references within a oneOf list.   The testcase mentioned below contains a fairly simple OpenAPI document (api.yaml) along with a custom rule which verifies that each schema contains a valid description.
The custom rule's function logs the individual paths that are visited, along with the individual violations that
are found.
The API contains a handful of re-usable (named) schemas, with one (Soda) that lacks a description.
This Soda schema is referenced from within the Drink schema's oneOf list and is reachable in three
different ways:
1. the post requestBody
2. the post response
3. the get response

**To Reproduce**
A testcase that demonstrates this problem can be found here:
https://github.com/padamstx/spectral-dedup-issue
The README.md contains detailed instructions to reproduce, but a summary is:
- clone the repo mentioned above
- `spectral lint api.yaml`

**Expected behavior**
Based on the way in which the api.yaml file is defined, I'd expect a single error to be displayed
by spectral with the path `components.schemas.Soda`

**Screenshots**
sample debug output from the custom function:
```sh
$ spectral lint api.yaml
Visiting path: paths./v1/drinks.post.requestBody.content.application/json.schema
Visiting path: paths./v1/drinks.post.requestBody.content.application/json.schema.oneOf.0
Visiting path: paths./v1/drinks.post.requestBody.content.application/json.schema.oneOf.0.properties.type
Visiting path: paths./v1/drinks.post.requestBody.content.application/json.schema.oneOf.0.properties.fruit
Visiting path: paths./v1/drinks.post.requestBody.content.application/json.schema.oneOf.1
>> Violation at: paths./v1/drinks.post.requestBody.content.application/json.schema.oneOf.1
Visiting path: paths./v1/drinks.post.requestBody.content.application/json.schema.oneOf.1.properties.type
Visiting path: paths./v1/drinks.post.requestBody.content.application/json.schema.oneOf.1.properties.name
Visiting path: paths./v1/drinks.post.responses.201.content.application/json.schema
Visiting path: paths./v1/drinks.post.responses.201.content.application/json.schema.oneOf.0
Visiting path: paths./v1/drinks.post.responses.201.content.application/json.schema.oneOf.0.properties.type
Visiting path: paths./v1/drinks.post.responses.201.content.application/json.schema.oneOf.0.properties.fruit
Visiting path: paths./v1/drinks.post.responses.201.content.application/json.schema.oneOf.1
>> Violation at: paths./v1/drinks.post.responses.201.content.application/json.schema.oneOf.1
Visiting path: paths./v1/drinks.post.responses.201.content.application/json.schema.oneOf.1.properties.type
Visiting path: paths./v1/drinks.post.responses.201.content.application/json.schema.oneOf.1.properties.name
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items.oneOf.0
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items.oneOf.0.properties.type
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items.oneOf.0.properties.fruit
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items.oneOf.1
>> Violation at: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items.oneOf.1
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items.oneOf.1.properties.type
Visiting path: paths./v1/drinks.get.responses.201.content.application/json.schema.properties.drinks.items.oneOf.1.properties.name

/home/padams/work/test/spectral-dedup-issue/api.yaml
 62:11  error  schema-description  Schema must have a non-empty description.  components.schemas.Drink.oneOf[1]
 75:17  error  schema-description  Schema must have a non-empty description.  components.schemas.Drinks.properties.drinks.items

✖ 2 problems (2 errors, 0 warnings, 0 infos, 0 hints)
```

**Environment:**
This problem was found in spectral v6.2.1 running on Linux (Fedora 34)

**Additional context**
This problem was originally discovered during development of custom rules as part of the IBM openapi-validator project (https://github.com/IBM/openapi-validator), which is tightly integrated with spectral.
