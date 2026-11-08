Remove duplication of accept_anything item validator
The function `accept_anything(item)` which acts as a validator that accepts all items is identical in  `trait_set_object`, `trait_dict_object` and `trait_list_object`

Need to move this to some central place and reused.

`trait_dict_object` and `trait_set_object` are under review and may not reflect this until merged. Issue for tracking.

### Additional contract requirements

- Default item validation is shared by `TraitList`, `TraitSet`, and
  `TraitDict` (for both keys and values), and accepts arbitrary items without
  changing them.
