decodeShortString : wrong answer of the function
**Describe the bug**
Hello,
I noted a problem with the function `utils/shortstrings.ts/decodeShortString`.
If I use it with an hex string ('0x321....456'), everything is fine.
But if the str:string is  an integer string ('1542233...56'), the function accept it, process without fail, and send back a wrong answer.
```typescript
export function decodeShortString(str: string) {
  return removeHexPrefix(str).replace(/.{2}/g, (hex) => String.fromCharCode(parseInt(hex, 16)));
}
```

**To Reproduce the problem :**
```typescript
const myText = "decimal number fail!";
console.log("myText =", myText);
const encodedText: string = shortString.encodeShortString(myText);
console.log("encodedText =", encodedText);
const myTextDecoded = shortString.decodeShortString(encodedText);
console.log("finalString =", myTextDecoded);
const decimalEncoded: string = BigInt(encodedText).toString(10);
console.log("decimalEncoded =", decimalEncoded);
const wrongTextDecoded : string= shortString.decodeShortString(decimalEncoded);
console.log("wrongTextDecoded =", wrongTextDecoded);
```
Result :
```
myText = decimal number fail!
encodedText = 0x646563696d616c206e756d626572206661696c21
finalString = decimal number fail!
decimalEncoded = 573160112338783013729123589963347449102752902177
wrongTextDecoded = W1`#8x0r#Xc4tI'R
```


**Expected behavior**
This function should handle properly both formats.

**Screenshots**
N/A

**Desktop (please complete the following information):**

- Browser & version : N/A
- Node version : "ts-node": "^10.9.1"
- StarkNet.js version : 4.21.0
- Network [ : N/A

**Additional context**
A PR is ready to send.
