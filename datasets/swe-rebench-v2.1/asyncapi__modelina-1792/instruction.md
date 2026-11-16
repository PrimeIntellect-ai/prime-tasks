TypeScript: attribute mapping in generated interface is incorrect
#### Describe the bug
I have attributes in my AsyncApi file that are of the format:
`aa_00_fooBar`

After using `TypeScriptGenerator` to generate the interfaces, the outputs in the generated interface are of the format:
`aa_00FooBar`

As visible, the second `_` is missing, with the following string title-cased instead of camel-cased.

#### How to Reproduce

Version `1.9.0`

##### Code to generate a typescript file with the generated interfaces:

```
import { TypeScriptGenerator } from "@asyncapi/modelina";
import { createWriteStream, readFileSync, unlinkSync } from "fs";

const OUTPUT_FILE = "output.ts";

const generator = new TypeScriptGenerator({ modelType: "interface" });
const contractJsonString = readFileSync("contract.json", { encoding: "utf-8" });
const contract = JSON.parse(contractJsonString);

export async function generate(): Promise<void> {
  const models = await generator.generate(contract);
  unlinkSync(OUTPUT_FILE);
  var stream = createWriteStream(OUTPUT_FILE, { flags: "a" });
  for (const model of models) {
    stream.write(model.result + "\n");
  }
  stream.end();
}

if (require.main === module) {
  generate();
}
```

##### contract.json
```
{
  "asyncapi": "2.6.0",
  "info": {
    "title": "Test",
    "version": "0.0.1"
  },
  "channels": {
    "test/test": {
      "publish": {
        "message": {
          "$ref": "#/components/messages/test"
        }
      }
    }
  },
  "components": {
    "messages": {
      "test": {
        "payload": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "aa_00_testAttribute": {
              "type": "string"
            },
            "aa_01_testAttribute": {
              "type": "string"
            },
            "aa_02_testAttribute": {
              "type": "string"
            }
          }
        }
      }
    }
  }
}
```

##### output.ts
```
interface AnonymousSchema_1 {
  aa_00TestAttribute?: string;
  aa_01TestAttribute?: string;
  aa_02TestAttribute?: string;
}
```

#### Expected behavior
Attributes in `AnonymousSchema_1` should be as such:
```
interface AnonymousSchema_1 {
  aa_00_testAttribute?: string;
  aa_01_testAttribute?: string;
  aa_02_testAttribute?: string;
}
```
