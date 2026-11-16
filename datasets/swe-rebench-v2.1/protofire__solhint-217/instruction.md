check-send-result is triggered when using require
Code:
```solidity
contract Foo {
    function sendEth(address _receiver, uint256 _value) public {
        require(_receiver.send(_value));
    }
}
```

the rule `check-send-result` is not triggered when using an `if` statement or assigning the result of `send` to a variable but it is triggered when using `require` or `assert`. I think the last two are also valid ways of checking the result.
