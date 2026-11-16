Generates c# source code that cannot be compiled.
### What are you generating using Kiota, clients or plugins?

API Client/SDK

### In what context or format are you using Kiota?

Nuget tool

### Client library/SDK language

Csharp

### Describe the bug

Given the following shortened API spec:

```yaml
openapi: 3.0.4
info:
  title: Process Parameter API
  version: 1.0.0

servers:
  - url: https://{ServerHost}
    variables:
      ServerHost:
        description: Host name and port of the server.
        default: localhost:9006

paths:
  /process-parameters:
    post:
      summary: Create a new process parameter
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ProcessParameter'
      responses:
        '201':
          description: Created
        '400':
          description: Bad Request

components:
  schemas:

    ProcessParameter:
      type: object
      description: Defines a single process parameter.
      properties:
        allowed_values:
          description: List of allowed values in case it's a numeric or string process parameter.
          nullable: true
          oneOf:
            - type: array
              items:
                type: number
            - type: array
              items:
                type: string
        key:
          type: string
          description: Key of the process parameter (acts as identifier).
          maxLength: 256
        station_id:
          type: string
          description: The id of the station the process parameter belongs to.
        kind:
          type: string
          enum: [BOOLEAN, NUMBER, STRING]
      required:
        - key
        - station_id
        - type
      example:
        key: /ST01/23992/VIBRATE
        station_id: ST01
        kind: BOOLEAN
```

```bash
C:\dev\Issue1
❯ kiota generate -l CSharp -c Client -n Issue1.Client -d ./OpenAPI-spec.yml -o ./Client
Generation completed successfully
Client base url set to https://{ServerHost}
```

Kiota generates source code that can not be compiled:

```bash
C:\dev\issue-1 via .NET v9.0.300 🎯 net9.0
❯ DOTNET_CLI_UI_LANGUAGE=en dotnet build
Restore complete (0,3s)
  issue-1 failed with 2 error(s) (0,2s)
    C:\dev\issue-1\Client\Models\ProcessParameter.cs(120,85): error CS8121: An expression of type 'List<double?>' cannot be handled by a pattern of type 'List<double>'.
    C:\dev\issue-1\Client\Models\ProcessParameter.cs(122,37): error CS0029: Cannot implicitly convert type 'System.Collections.Generic.List<double>' to 'System.Collections.Generic.List<double?>'

Build failed with 2 error(s) in 0,7s
```

Problematic code:
```csharp
/// <summary>
/// Creates a new instance of the appropriate class based on discriminator value
/// </summary>
/// <returns>A <see cref="global::Issue1.Client.Models.ProcessParameter.ProcessParameter_allowed_values"/></returns>
/// <param name="parseNode">The parse node to use to read the discriminator value and create the object</param>
public static global::Issue1.Client.Models.ProcessParameter.ProcessParameter_allowed_values CreateFromDiscriminatorValue(IParseNode parseNode)
{
	_ = parseNode ?? throw new ArgumentNullException(nameof(parseNode));
	var mappingValue = parseNode.GetChildNode("")?.GetStringValue();
	var result = new global::Issue1.Client.Models.ProcessParameter.ProcessParameter_allowed_values();
	if(parseNode.GetCollectionOfPrimitiveValues<double?>()?.AsList() is List<double> doubleValue)
	{
		result.Double = doubleValue;
	}
	else if(parseNode.GetCollectionOfPrimitiveValues<string>()?.AsList() is List<string> stringValue)
	{
		result.String = stringValue;
	}
	return result;
}
```


### Expected behavior

Source code does compile by eg. producing:

```csharp
if(parseNode.GetCollectionOfPrimitiveValues<double?>()?.AsList() is List<double?> doubleValue)
```
instead of:

```csharp
if(parseNode.GetCollectionOfPrimitiveValues<double?>()?.AsList() is List<double> doubleValue)
```

### How to reproduce

```bash
mkdir Issue1
cd Issue1
dotnet new console
# store API spec as OpenAPI-spec.yml
kiota generate -l CSharp -c Client -n Issue1.Client -d ./OpenAPI-spec.yml -o ./Client
dotnet add package Microsoft.Kiota.Bundle
dotnet build
```

### Open API description file

```yaml
openapi: 3.0.4
info:
  title: Process Parameter API
  version: 1.0.0

servers:
  - url: https://{ServerHost}
    variables:
      ServerHost:
        description: Host name and port of the server.
        default: localhost:9006

paths:
  /process-parameters:
    post:
      summary: Create a new process parameter
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ProcessParameter'
      responses:
        '201':
          description: Created
        '400':
          description: Bad Request

components:
  schemas:

    ProcessParameter:
      type: object
      description: Defines a single process parameter.
      properties:
        allowed_values:
          description: List of allowed values in case it's a numeric or string process parameter.
          nullable: true
          oneOf:
            - type: array
              items:
                type: number
            - type: array
              items:
                type: string
        key:
          type: string
          description: Key of the process parameter (acts as identifier).
          maxLength: 256
        station_id:
          type: string
          description: The id of the station the process parameter belongs to.
        kind:
          type: string
          enum: [BOOLEAN, NUMBER, STRING]
      required:
        - key
        - station_id
        - type
      example:
        key: /ST01/23992/VIBRATE
        station_id: ST01
        kind: BOOLEAN
```

### Kiota Version

1.26.1+a5df7c03bab621bb2d4dc728516fc9c488cabadb

### Latest Kiota version known to work for scenario above?(Not required)

_No response_

### Known Workarounds

_No response_

### Configuration

- Windows 10
- x64
- no

### Debug output

<details><summary>Click to expand log</summary>
```bash


C:\dev\Issue1 via .NET v9.0.300 🎯 net9.0
❯ kiota update --ll debug --clean-output --output .
info: Kiota.Builder.KiotaBuilder[0]
      Cleaning output directory C:\dev\Issue1\.\Client
dbug: Kiota.Builder.KiotaBuilder[0]
      kiota version 1.26.1
info: Kiota.Builder.KiotaBuilder[0]
      loaded description from local source
dbug: Kiota.Builder.KiotaBuilder[0]
      step 1 - reading the stream - took 00:00:00.0055954
dbug: Kiota.Builder.KiotaBuilder[0]
      step 2 - parsing the document - took 00:00:00.0660983
dbug: Kiota.Builder.KiotaBuilder[0]
      step 3 - updating generation configuration from kiota extension - took 00:00:00.0000773
dbug: Kiota.Builder.KiotaBuilder[0]
      step 4 - filtering API paths with patterns - took 00:00:00.0036079
info: Kiota.Builder.KiotaBuilder[0]
      Client root URL set to https://{ServerHost}
dbug: Kiota.Builder.KiotaBuilder[0]
      step 5 - checking whether the output should be updated - took 00:00:00.0115690
dbug: Kiota.Builder.KiotaBuilder[0]
      step 6 - create uri space - took 00:00:00.0022967
dbug: Kiota.Builder.KiotaBuilder[0]
      InitializeInheritanceIndex 00:00:00.0022914
dbug: Kiota.Builder.KiotaBuilder[0]
      CreateRequestBuilderClass 00:00:00
dbug: Kiota.Builder.KiotaBuilder[0]
      MapTypeDefinitions 00:00:00.0040606
dbug: Kiota.Builder.KiotaBuilder[0]
      TrimInheritedModels 00:00:00
dbug: Kiota.Builder.KiotaBuilder[0]
      CleanUpInternalState 00:00:00
dbug: Kiota.Builder.KiotaBuilder[0]
      step 7 - create source model - took 00:00:00.0514567
dbug: Kiota.Builder.KiotaBuilder[0]
      16ms: Language refinement applied
dbug: Kiota.Builder.KiotaBuilder[0]
      step 8 - refine by language - took 00:00:00.0169586
dbug: Kiota.Builder.KiotaBuilder[0]
      step 9 - writing files - took 00:00:00.0262235
info: Kiota.Builder.KiotaBuilder[0]
      loaded description from local source
dbug: Kiota.Builder.KiotaBuilder[0]
      step 10 - writing lock file - took 00:00:00.0068137
Update of Client client for CSharp at C:\dev\Issue1\.\Client completed
Client base url set to https://{ServerHost}
Update of 1 clients completed successfully

```
</details>


### Other information

❯ dotnet --version
9.0.300

### Additional contract requirements

- For a nullable numeric collection in a generated C# union factory, the deserialization call must use `GetCollectionOfPrimitiveValues<double?>`, and the generated code must not contain `List<double>`.
