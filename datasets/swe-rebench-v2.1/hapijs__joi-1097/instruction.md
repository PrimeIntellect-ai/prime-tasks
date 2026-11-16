Joi wrong value parsing
#### Context
- _node v6.2.0_:
- _joi 9.0.0_:
- _used with_ (expressjs):

``` js
const validator = Joi.object({
            name: Joi.string(),
            pricing_formula: Joi.string(),
            period: Joi.string().valid(Object.keys(this.model.PERIODS)).allow(null),
            is_active: Joi.boolean(),
            formula_variables: Joi.array().items(Joi.object({
                name: Joi.string(),
                type: Joi.string().valid(Object.keys(models.PricingFormulaVariable.TYPES)),
                value: Joi.alternatives().when('type', {
                    is: models.PricingFormulaVariable.TYPES.constant_map,
                    then: Joi.object({
                        default: Joi.number().integer().min(0)
                    }).required()/*.pattern(/[\w\d]+/, Joi.number().integer().min(0))*/,
                    otherwise: Joi.number().integer().min(0)
                }),
            })).unique((a, b) => a.name === b.name)
        }).options({
            allowUnknown: false,
            abortEarly: false,
            presence: 'required'
        });

const validatedBody = Joi.attempt({
                name: 'hello',
                pricing_formula: 'a + b + c',
                period: null,
                is_active: true,
                formula_variables: [
                    {
                        name: 'a',
                        type: 'variable',
                        value: 100
                    },
                    {
                        name: 'b',
                        type: 'constant',
                        value: 0
                    },
                    {
                        name: 'c',
                        type: 'constant_map',
                        value: '{}'
                    }
                ]
            }, validator);
```
#### Which result you had ?

Cannot create property '_$miss$_default|1_$end$_' on string '{}'
#### What did you expect ?

```
{
   isJoi:true,
   name:"ValidationError",
   details:[
      {
         message:""         value" must be an object",
         path:"formula_variables.2.value",
         type:"object.base",
         context:{
            key:"value"
         }
      }
   ],
   _object:{
      name:"hello",
      pricing_formula:"a + b + c",
      period:null,
      is_active:true,
      formula_variables:[
         {
            name:"a",
            type:"variable",
            value:100
         },
         {
            name:"b",
            type:"constant",
            value:0
         },
         {
            name:"c",
            type:"constant_map",
            value:"{}"
         }
      ]
   }
}
```

### Additional contract requirements

- When validating `{ a: '{"c":"string"}' }` against `{ a: Joi.object({ b: Joi.string() }) }` with `abortEarly: false`, `err.annotate(true)` must equal:

```text
{
  "a" [1]: "{\"c\":\"string\"}"
}

[1] "c" is not allowed
```

- For the supplied input, validation must fail with a Joi validation error rather than throwing a TypeError. The error is reported at a path under `formula_variables.2.value`; the exact error type and message are not fixed.
- Additionally, calling `Joi.attempt` with `{ a: '{"c":"string"}' }` against `{ a: Joi.object({ b: Joi.string() }) }` must throw an error whose message contains `"c" is not allowed`.
