Issue with nesting oneOf inside an array that is inside of an object.
### Prerequisites

- [x] I have read the [documentation](https://react-jsonschema-form.readthedocs.io/);
- [x] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.
- [x] Ideally, I'm providing a [sample JSFiddle](https://jsfiddle.net/n1k0/f2y3fq7L/6/) or a [shared playground link](https://mozilla-services.github.io/react-jsonschema-form/) demonstrating the issue.

### Description

I am attempting to use oneOf to create an array, which will be filled with objects. These objects will have a string along with an array.
this is the expected formData or object I want to receive on the backend:
```
{
typeProp: 'verify',
verifications: [
  {
    service: 'myService',
    endpoints: [
      {
        Description: 'myService1',
        Id: ''
      },
      {
        Description: 'myService2',
        Id: ''
      },
      {
        Description: 'myService3',
        Id: ''
      }
    ]
  },
  {
    serviceName: 'yourService',
    endpoints: [
      {
        endpointDescription: 'yourService1',
        endpointId: ''
      },
      {
        endpointDescription: 'yourService2',
        endpointId: ''
      }
    ]
  }
]
}
```

I am trying to use a dropdown on my typeProp, which would then show a dropdown for the service, once a selection is made for the service, I need the endpoints to show and also be a dropdown. Basically, all 3 fields will need to be a oneOf dropdown.

Now, oneOf seems to be the best solution for me. However, the oneOf functionality does not seem to be able to be nested. Is there a way around this? Does anyone have a solution to my problem, or is this a bug in the code that will need to be reviewed? Any help is greatly appreciated

I'm not sure how to add a playground, but here is the code I currently have. I have tried every thing imagine-able of where to put the next oneOf but cannot find a solution.

Here is my code:
```
{
      title: 'New,
      description: 'Create',
      type: 'object',
      properties: {
        type: {
          type: 'string',
          title: 'Type',
          enum: [
            'verification',
            'subscription'
          ]
        }
      },
      dependencies: {
        type: {
          oneOf: [
            {
              properties: {
                type: {
                  enum: ['verification']
                },
                verification: {
                  type: 'array',
                  title: 'Verifications',
                  items: {
                    type: 'object',
                    properties: {
                      serviceName: {
                        type: 'string',
                        title: 'Service Name',
                        enum: ['myService']
                      },
                      endpoints: {
                        type: 'array',
                        title: 'End Points',
                        items: {
                          type: 'object',
                          properties: {
                            endpointDesc: {
                              type: 'string',
                              title: 'EP Name',
                              enum: ['MyServiceEP']
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          ]
        }
      }
    }
```

### Additional contract requirements

The nested oneOf selections must be reflected in the formData that the form
produces. Selecting a nested oneOf option must keep that option selected while
the nested data is edited, so that the fields belonging to the selected option
remain available. For a schema with a `typeProp` string field and a `verifications` array whose items are a oneOf
between a `service` option and a `serviceName` option (each carrying an
`endpoints` array whose items are a oneOf between a `Description` option and an
`endpointDescription` option), selecting the `serviceName` option, adding an
endpoint, selecting the `endpointDescription` option, and entering the values
`verify`, `yourService` and `yourService1` must yield the formData:
```json
{
  "typeProp": "verify",
  "verifications": [
    {
      "serviceName": "yourService",
      "endpoints": [{ "endpointDescription": "yourService1" }]
    }
  ]
}
```
