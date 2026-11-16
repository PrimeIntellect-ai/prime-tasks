Struct-valued constants are not yet implemented
As it stands today, the current thrifty schema is not able to parse struct valued constants. Wanted to know if this is a work in progress? If not, was this something consciously left out from implementation?

I am trying to load schemas for manipulating certain exceptions based on added annotations. Given that we only care about exceptions structs, is it possible to silently fail the constant schema generation so that it does not throw `IllegalStateException`?

Several of our thrift definitions have struct valued constants so wondering if there is any workaround?

### Additional contract requirements

- When loading a `Region` struct-valued constant with a non-string key, the failure message must contain `Region struct const keys must be string`. When a `Region` struct-valued constant names a nonexistent field `nonActive`, the failure message must contain `Region struct has no field nonActive`. When a `Region` struct-valued constant uses `Membership.WRONG` for a `Membership` enum field whose members are `MEMBER`, `NON_MEMBER`, and `UNDER_REVIEW`, the failure message must contain `'Membership.WRONG' is not a member of enum type Membership: members=[MEMBER, NON_MEMBER, UNDER_REVIEW]`.
