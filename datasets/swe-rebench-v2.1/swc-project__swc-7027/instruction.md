Wrong output for "jsc.transform.constModules" configuration with object const
### Describe the bug

After update from **v1.3.37** to **v1.3.38** we noticed different output for [**jsc.transform.constModules**](https://swc.rs/docs/configuration/compilation#jsctransformconstmodules) for modules that contain non-primitive data.



### Input code

```typescript
import { testMap } from "testModule";
testMap['var'];
```


### Config

```json
{
  "jsc": {
    "target": "es2021",
    "parser": {
      "syntax": "typescript"
    },
    "transform": {
      "constModules": {
        "globals": {
          "testModule": {
            "testMap": "{ 'var': 'value' }"
          }
        }
      }
    }
  }
}
```


### Playground link

https://play.swc.rs/?version=1.3.38&code=H4sIAAAAAAAAA8vMLcgvKlGoVihJLS7xTSxQqFVIK8rPVVAC8%2FNTSnNSlay5oJLR6mWJReqx1gD907e3NQAAAA%3D%3D&config=H4sIAAAAAAAAAz1MOw6DMAy9CvKShYEy5g4cwg0GtUqTyDYVKMrd61Rq3%2FK%2BehWeEsBXKMhC3JVcSfEED3oVksCPotBGUMYkW%2BZX34ScRJe8HpGk%2Bz3mO8avVPo1f4fF3urg3sjOd4oHuaFBM9gx8k5qC5J5mm%2BWfgDY4jojlQAAAA%3D%3D

### Expected behavior

Output has to be like in v1.3.37 and earlier:
```
({
    'var': 'value'
})['var'];
```

### Actual behavior

```
testMap['var'];
```

### Version

v1.3.38

### Additional context

_No response_
