How to avoid using dot notation in filters input source and use as is
Hi,

I would like to use nested properties filters https://api-platform.com/docs/core/filters/#filtering-on-nested-properties
but in order to do so I need to provide querystring like this `endpoint?city.name=search`
which I cannot do because `react-admin` filter will generate `endpoint?city[name]=search` out of next example due to dot notation thing.
```js
<Filter {...props}>
    <TextInput label='City' source='`city.name`' alwaysOn />
</Filter>
```

It looks like it goes into `redux-form` and `jsx` feature set, but how do I escape dot in this case?

Cheers.
wrong syntax of query string parameters for multiple values of search filter
Hello

I'm truly a beginner in react.
I would like to use a search filter in order to searching multiple values for the same property. I saw it was possible and applied the annotation filter in my entity like this :

`@ApiFilter(SearchFilter::class, properties={"brands": "exact",})`

and wrote my react-admin filter in that way to select multiple values :

```
<Filter {...props}>
	<ReferenceArrayInput label="Services" source="brands" reference="services">
                <SelectArrayInput source="id"  optionText="name" >
	</ReferenceArrayInput>
</Filter>
```
When I pick one value, it works, however beyond one value picked, it throws a internal server error. It seems that instead of sending query string parameters like this (the right way) :

`brands[]=/services/1&brands[]=/services/2`

my request send :

`brands=/services/1,/services/2`

and throws that error :

```
@context: "/contexts/Error", @type: "hydra:Error", hydra:title: "An error occurred",…}
@context: "/contexts/Error"
@type: "hydra:Error"
hydra:description: "An exception occurred while executing
   'SELECT DISTINCT o0_.id AS id_0, o0_.name AS name_1, o0_.id AS id_2
    FROM organization o0_
    LEFT JOIN organization_service o2_ ON o0_.id = o2_.organization_id
    LEFT JOIN service s1_ ON s1_.id = o2_.service_id
    WHERE o0_.id IN (SELECT o3_.id FROM organization o3_
		LEFT JOIN organization_service o5_ ON o3_.id = o5_.organization_id
		LEFT JOIN service s4_ ON s4_.id = o5_.service_id WHERE s4_.id = ?)
		ORDER BY o0_.name ASC, o0_.id ASC LIMIT 30'
		with params ["\/services\/1,\/services\/2"]:↵↵SQLSTATE[22P02]: Invalid text representation:
		7 ERROR:  invalid input syntax for integer: "/services/1,/services/2""
hydra:title: "An error occurred"
```
Would you have any ideas to help me with that please ?
Thanks.

### Additional contract requirements

- `src/hydra/dataProvider.js` exposes a default export `dataProvider(entrypoint, fetcher)`, where `entrypoint` is the base URL of the Hydra API and `fetcher` is a function that performs the HTTP request. It returns a data-provider function `(type, resource, params) => Promise`.
- The returned data-provider function resolves to an object with `data` (an array of transformed Hydra members) and `total` (the `hydra:totalItems` value of the Hydra response). Errors raised by the fetcher are propagated to the caller.
- The module also exposes a named export `transformJsonLdDocumentToReactAdminDocument(document)` that returns a deep clone of the document in which `id` is set to the original `@id`, the original `id` is preserved as `originId`, `toString()` returns `"[object " + @id + "]"`, and every embedded document (an object carrying an `@id`) is replaced by its IRI string, including inside arrays.
