mark-callable-contracts rule is firing a false positive on enums
The mark-callable-contracts rule is being triggered against enums (similar to #114 and #118).

Simple contract to reproduce the issue:
```
pragma solidity 0.5.9;

contract Example {

    enum Status { Initial }

    Status public status;

    constructor() public {
        status = Status.Initial;
    }

}
```

Produces the following warnings:
```
10:18  warning  Explicitly mark all external contracts as trusted or untrusted  mark-callable-contracts
10:25  warning  Explicitly mark all external contracts as trusted or untrusted  mark-callable-contracts
```
