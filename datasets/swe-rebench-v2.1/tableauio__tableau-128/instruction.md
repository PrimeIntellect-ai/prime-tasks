union: support horizontal/vertical union list
### Predefined in proto
A `union` type should be predefined:

```protobuf
// Predefined union type.
message Target {
  option (tableau.union) = true;

  Type type = 9999 [(tableau.field) = { name: "Type" }];
  oneof value {
    option (tableau.oneof) = {
      field: "Field"
    };
    Pvp pvp = 1;      // Bound to enum value 1: TYPE_PVP.
    Pve pve = 2;      // Bound to enum value 2: TYPE_PVP.
    Story story = 3;  // Bound to enum value 3: TYPE_STORY.
    Skill skill = 4;  // Bound to enum value 4: TYPE_SKILL.
  }

  enum Type {
    TYPE_NIL = 0;
    TYPE_PVP = 1 [(tableau.evalue) = { name: "PVP" }];
    TYPE_PVE = 2 [(tableau.evalue) = { name: "PVE" }];
    TYPE_STORY = 3 [(tableau.evalue) = { name: "Story" }];
    TYPE_SKILL = 4 [(tableau.evalue) = { name: "Skill" }];
  }
  message Pvp {
    int32 type = 1;                          // scalar
    int64 damage = 2;                        // scalar
    repeated protoconf.FruitType types = 3;  // incell enum list
  }
  message Pve {
    Mission mission = 1;             // incell struct
    repeated int32 heros = 2;        // incell list
    map<int32, int64> dungeons = 3;  // incell map

    message Mission {
      int32 id = 1;
      uint32 level = 2;
      int64 damage = 3;
    }
  }
  message Story {
    protoconf.Item cost = 1;                     // incell predefined struct
    map<int32, protoconf.FruitType> fruits = 2;  // incell map with value as enum type
    map<int32, Flavor> flavors = 3;              // incell map with key as enum type
    message Flavor {
      protoconf.FruitFlavor key = 1 [(tableau.field) = { name: "Key" }];
      int32 value = 2 [(tableau.field) = { name: "Value" }];
    }
  }
  message Skill {
    int32 id = 1;      // scalar
    int64 damage = 2;  // scalar
    // no field tag 3
  }
}
```
## Horizontal union list
| ID |Target1Type | Target1Field1 | Target1Field2 | Target1Field3 |Target2Type | Target2Field1 | Target2Field2 | Target2Field3 |
|--|--|--|--|--|--|--|--|--|
| map<int32, Task> |  [.Target]enum<.Target.Type> | union| union | union |enum<.Target.Type> | union| union | union |
| ID | Target1's type | Target1's value field1 | Target1's value field2 | Target1's value field3 |Target2's type | Target2's value field1 | Target2's value field2 | Target2's value field3 |
| 1 | PVP | 1 | 10 | 100 | PVE | 1,100,999| 1,2,3 | 1:10,2:20,3:30 |
| 2 | PVE | 1,100,999| 1,2,3 | 1:10,2:20,3:30 |PVP | 1 | 10 | 100 |

## TODO
- [ ] #129
