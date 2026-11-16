[BUG] "Unexpected end of data" during bigintToBytes()
### Current Behavior

biginToBytes() converts a bigInt to a hex string, which sometimes misses left padding, which causes a conversion error

### Expected Behavior

biginToBytes() converts a bigInt to a hex string

### Failure Information

Solution:
```ts
[HIDDEN]
```

Issue we found: https://github.com/Tonomy-Foundation/Tonomy-App-Websites/issues/76
Solution we made: https://github.com/Tonomy-Foundation/Tonomy-ID-SDK/pull/228/files#diff-4335ca2354d2963bc461d6d160ca76c2ac0bd3524a6a8eaba6c627407ca1cf41R26

#### Steps to Reproduce

```ts
const bi = 1881146970754576322752261068397796891246589699629597037555588131642783231506n
const biBytes = bigintToBytes(bi);
const base64 = bytesToBase64(biBytes);
expect(base64).toBe('BCixAySH6XqSNMR6MVnd4SCluKq3Ey5RQIy0/0Eu7hI=');
// fails with error "Unexpected end of data"

const bi = 100968908336250941489582664670319762383316987426946165788206218268821633081179n
const biBytes = bigintToBytes(bi);
const base64 = bytesToBase64(biBytes);
expect(base64).toBe('3zpgfkpIN/0k/xkychS26ElYP4Bnb24RcYACzsbzn1s=');
// succeeds
```

#### Environment Details

* node version: v18.12.1
* OS Version: ubuntu 20.04
