Add support for offline Entity create and update
Spec discussion at https://forum.getodk.org/t/form-spec-proposal-support-entity-updates-from-multiple-offline-clients/47890

We are going to stage this. In the next version of `pyxform`, users will need to explicitly opt in to produce forms that use the v2024.1.0 spec to use offline Entities to allow for some piloting of the functionality across all components. The opt-in flag will be removed in the following version and all Entity-related forms will be produced following the v2024.1.0 spec.

Entity-related forms can create or update Entities or do both. There is existing logic in `pyxform` to determine which of these a form definition specifies.

## Forms that can create Entities
For forms that can create Entities, the only change needed in `pyxform` is to set the `entities-version` attribute on the `model` node to `2024.1.0`.

## Forms that can update Entities
For forms that can update Entities, the `entities-version` attribute on the `model` node will need to be set to `2024.1.0`.

Additionally:
* Add `trunkVersion` and `branchId` attributes to the `entity` element
* Add the following `binds`:
```
<bind nodeset="/data/meta/entity/@trunkVersion" type="string" calculate="instance('trees')/root/item[name=/data/tree]/__trunkVersion" />
<bind nodeset="/data/meta/entity/@branchId" type="string" calculate="instance('trees')/root/item[name=/data/tree]/__branchId" />
```

## Opt in
Initially, the changes described above should be opt-in so we also need to introduce a setting column named `offline` on the `entities` sheet. It should be optional and its default value should be `no`/`false`. If its value is set to `yes`, the changes above should be applied. Otherwise, Entity forms should be generated as they are today.

### Additional contract requirements

- Each of these binds must also include `readonly="true()"`.
- For an offline update form with dataset `trees`, entity ID `${id}`, and root node `/test_name`, the `calculate` attributes on the `trunkVersion` and `branchId` binds must be exactly `instance('trees')/root/item[name= /test_name/id ]/__trunkVersion` and `instance('trees')/root/item[name= /test_name/id ]/__branchId`, respectively.
- The module `pyxform.constants` must expose a public constant `ENTITIES_OFFLINE_VERSION` whose value is the string `"2024.1.0"`, and a public constant `ENTITIES_UPDATE_VERSION` whose value is the string `"2023.1.0"`. The existing public constant `ENTITIES_CREATE_VERSION` must retain the value `"2022.1.0"`.


- If the `offline` setting is omitted, it defaults to no: Entity forms retain their existing behavior.
- Opting in to offline support does not change whether a form creates Entities, updates Entities, or does both.
