Throttle uses consumer validator address to lookup validator power but it should use provider address
# Problem

The slash throttle uses the consumer validator address to lookup the voting power on the provider in order to subtract from the slash meter, so it will not find any validator if a consumer key is assigned. It will get always retrieve `0` power.

# Closing criteria

Ensure the validator power is queried using the provider validator address

# Problem details

Slash is queued

https://github.com/cosmos/interchain-security/blob/goc-december/x/ccv/provider/keeper/relay.go#L243-L256

Validator power is looked up

https://github.com/cosmos/interchain-security/blob/circuit-breaker/x/ccv/provider/keeper/throttle.go#L18-L37

# TODOs
- [x] Labels have been added for issue
- [x] Issue has been added to the ICS project
