Example request and response
How to add Example request and response to an endpoint. When writing API documentation, you would usually want to provide your users with sample request body to guide how the request payload should be constructed and formatted and also provide at least a sample returned response to showcase the format of the response

**Describe the solution you'd like**
/**
*@example  {requestBody} - a sample request body
 {
          "username": "LA-AM-0001",
          "password": "PMNmj@123",
          "firstName": "segufkn",
          "lastName": "IDEklmhj",
          "dob": "2000-07-08",
          "gender": "Male",
          "role": "master-agent",
          "phone": {
            "code": "234",
            "number": "807489388"
          }
*@example  {responseBody} - a sample request body
{
          "status": true,
          "message": "user registered successfully",
          "data": {
            "username": "LA-AM-0001",
            "firstName": "segufkn",
            "lastName": "IDEklmhj",
            "dob": "04-26-202",
            "gender": "Male",
            "role": "master-agent",
            "phone": {
              "code": "234",
              "number": "807489388"
            },
            "wallet": {
              "balance": 20000,
              "ledgerBalance": 20000,
              "trust": 0
            }
          }
        }
*/

### Additional contract requirements

- Use `@example request - <summary>` followed by the example body text for a request example, and `@example response - <status> - <summary>` followed by the example body text for a response example. In the generated path output, a request example appears at `requestBody.content['application/json'].examples.example1` with its `summary` and body text as `value`. Response examples appear under `responses[<status>].content['application/json'].examples`; the first is named `example1` and the next `example2`, including when they belong to different statuses. Each response example has its `summary` and exact body text as `value`.
