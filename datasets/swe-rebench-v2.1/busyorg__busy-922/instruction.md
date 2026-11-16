SP amount in "Claim Rewards" transactions is not SP
#### Expected behavior

The number in Claim Rewards transactions should be actually SP.

![image](https://user-images.githubusercontent.com/16621517/32141739-f5b2b95c-bc87-11e7-91f3-62c63778e33d.png)

#### Actual behavior

The number is much higher. It seems that it is VESTS (not confirmed).

![image](https://user-images.githubusercontent.com/16621517/32141741-fa3a4cc4-bc87-11e7-9cbe-84e51a7845a4.png)

#### How to reproduce

1. Go to wallet
2. Find "Claim Rewards" transaction
3. Compare with Steemit

* Browser: Chrome
* Operating system: Windows 10

### Additional contract requirements

- In Claim Rewards transactions, display the `rewardVests` reward converted to Steem Power (SP) using `totalVestingShares` and `totalVestingFundSteem`, rather than displaying the raw vesting amount.
