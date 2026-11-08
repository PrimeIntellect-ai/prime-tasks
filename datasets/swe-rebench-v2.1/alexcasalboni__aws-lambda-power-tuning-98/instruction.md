Invalid Parameter Type: Expected params. Payload to be a string, Buffer, Stream, Blob, or typed array object.
Hi,
I have an issue when providing this type of weighted payload value:
```json
{
  "lambdaARN": "my_lambda_ARN",
  "powerValues": [
    128,
    256,
    512,
    1024,
    2048,
    3008
  ],
  "num": 10,
  "payload": [
    {
      "payload": {
        "body-json": {
          "dateRanges": [
            {
              "start": "2020-05-01",
              "end": "2020-05-31"
            },
            {
              "start": "2020-04-01",
              "end": "2020-04-30"
            }
          ]
        },
        "params": {
          "path": {
            "tenantId": "DA29004"
          },
          "querystring": {},
          "header": {
            "Authorization": "Bearer some_bearer"
          }
        }
      },
      "weight": 1
    },
    {
      "payload": {
        "body-json": {
          "dateRanges": [
            {
              "start": "2020-05-01",
              "end": "2020-05-31"
            },
            {
              "start": "2020-03-01",
              "end": "2020-03-31"
            }
          ]
        },
        "params": {
          "path": {
            "tenantId": "DA29004"
          },
          "querystring": {},
          "header": {
            "Authorization": "Bearer some_bearer"
          }
        }
      },
      "weight": 1
    },
    {
      "payload": {
        "body-json": {
          "dateRanges": [
            {
              "start": "2020-05-01",
              "end": "2020-05-31"
            },
            {
              "start": "2020-02-01",
              "end": "2020-02-29"
            }
          ]
        },
        "params": {
          "path": {
            "tenantId": "DA29004"
          },
          "querystring": {},
          "header": {
            "Authorization": "Bearer some_bearer"
          }
        }
      },
      "weight": 1
    }
  ],
  "parallelInvocation": false,
  "strategy": "balanced"
}
```

It results with:
```json
"error": {
    "Error": "InvalidParameterType",
    "Cause": "{\"errorType\":\"InvalidParameterType\",\"errorMessage\":\"Expected params.Payload to be a string, Buffer, Stream, Blob, or typed array object\",\"trace\":[\"InvalidParameterType: Expected params.Payload to be a string, Buffer, Stream, Blob, or typed array object\",\"    at ParamValidator.fail (/var/runtime/node_modules/aws-sdk/lib/param_validator.js:50:37)\",\"    at ParamValidator.validatePayload (/var/runtime/node_modules/aws-sdk/lib/param_validator.js:267:10)\",\"    at ParamValidator.validateScalar (/var/runtime/node_modules/aws-sdk/lib/param_validator.js:133:21)\",\"    at ParamValidator.validateMember (/var/runtime/node_modules/aws-sdk/lib/param_validator.js:94:21)\",\"    at ParamValidator.validateStructure (/var/runtime/node_modules/aws-sdk/lib/param_validator.js:75:14)\",\"    at ParamValidator.validateMember (/var/runtime/node_modules/aws-sdk/lib/param_validator.js:88:21)\",\"    at ParamValidator.validate (/var/runtime/node_modules/aws-sdk/lib/param_validator.js:34:10)\",\"    at Request.VALIDATE_PARAMETERS (/var/runtime/node_modules/aws-sdk/lib/event_listeners.js:126:42)\",\"    at Request.callListeners (/var/runtime/node_modules/aws-sdk/lib/sequential_executor.js:106:20)\",\"    at callNextListener (/var/runtime/node_modules/aws-sdk/lib/sequential_executor.js:96:12)\"]}"
  }
```

Now, I do not know why this is happening and what it actually means. There are three objects in payload array. When I remove one. Execution is successful. It is payload for Lambda used for POST requests.

### Additional contract requirements

For the reported weighted input with three object payloads and `num` set to 10, all 10 Lambda invocations must receive valid string-encoded payloads drawn from the supplied payload list; no invocation should receive an unfilled payload.
