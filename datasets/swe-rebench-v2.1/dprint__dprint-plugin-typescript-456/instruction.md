Consider wide unicode characters in `lineWidth`
**Describe the bug**

- dprint-plugin-typescript version: 0.78.0
- lineWidth: 80
- indentWidth: 2
- useTabs: false

**Input Code**

```tsx
const a = () => (
  <div>
    대충 한국어로 아무 말이나 적고 있습니다. '아무말'은 표준국어대사전에 등재되지 않은 단어이므로 '아무 말'로 띄어 씁니다. 아무 말일까요? 누군가에게는 적절한 더미 텍스트일 수도 있고 누군가에게는 그냥 지루한 문단일 수 있습니다. 문장이 긴데 보여질 폭은 좁을 때 어디에서 줄바꿈을 해야 할지는 중요한 이슈가 되어 왔습니다. 한국어는 띄어쓰기가 자주 등장하는 만큼 단어 사이를 끊는 것을 싫어하지만 끊는 부분에 타우마타와카탕이항아코아우아우오타마테아투리푸카카피키마웅아호로누쿠포카이웨누아키타나타후 같은 단어가 존재하면 엄청난 공백이 등장하게 됩니다. 직접 줄바꿈을 삽입하자는 의견도 나오지만 다양한 스크린 폭에 대응되지 못하는 것을 탐탁치 않아 하는 사람도 있습니다. 대충 한국어로 아무 말이나 적었습니다.
  </div>
);
```

**Expected Output**

```tsx
const a = () => (
  <div>
    대충 한국어로 아무 말이나 적고 있습니다. '아무말'은 표준국어대사전에
    등재되지 않은 단어이므로 '아무 말'로 띄어 씁니다. 아무 말일까요?
    누군가에게는 적절한 더미 텍스트일 수도 있고 누군가에게는 그냥 지루한 문단일
    수 있습니다. 문장이 긴데 보여질 폭은 좁을 때 어디에서 줄바꿈을 해야 할지는
    중요한 이슈가 되어 왔습니다. 한국어는 띄어쓰기가 자주 등장하는 만큼 단어
    사이를 끊는 것을 싫어하지만 끊는 부분에
    타우마타와카탕이항아코아우아우오타마테아투리푸카카피키마웅아호로누쿠포카이웨누아키타나타후
    같은 단어가 존재하면 엄청난 공백이 등장하게 됩니다. 직접 줄바꿈을 삽입하자는
    의견도 나오지만 다양한 스크린 폭에 대응되지 못하는 것을 탐탁치 않아 하는
    사람도 있습니다. 대충 한국어로 아무 말이나 적었습니다.
  </div>
);
```
Got from [Prettier playground].

**Actual Output**

```tsx
const a = () => (
  <div>
    대충 한국어로 아무 말이나 적고 있습니다. '아무말'은 표준국어대사전에 등재되지 않은 단어이므로 '아무 말'로 띄어 씁니다. 아무
    말일까요? 누군가에게는 적절한 더미 텍스트일 수도 있고 누군가에게는 그냥 지루한 문단일 수 있습니다. 문장이 긴데 보여질 폭은 좁을 때
    어디에서 줄바꿈을 해야 할지는 중요한 이슈가 되어 왔습니다. 한국어는 띄어쓰기가 자주 등장하는 만큼 단어 사이를 끊는 것을 싫어하지만
    끊는 부분에 타우마타와카탕이항아코아우아우오타마테아투리푸카카피키마웅아호로누쿠포카이웨누아키타나타후 같은 단어가 존재하면 엄청난 공백이
    등장하게 됩니다. 직접 줄바꿈을 삽입하자는 의견도 나오지만 다양한 스크린 폭에 대응되지 못하는 것을 탐탁치 않아 하는 사람도 있습니다.
    대충 한국어로 아무 말이나 적었습니다.
  </div>
);
```
Got from [dprint playground].

CJK and Emoji characters are usually considered as 2 half-width characters. I think, but I'm unsure, that other dprint plugins (or dprint itself) also have this problem.

[Prettier playground]: https://prettier.io/playground/#N4Igxg9gdgLgprEAuc0DOMAEBDTBeTACgEp8A+IgHSk0wB4ATASwDczrbbAAZsErZzQHVXAtrWAW0cA6HZkAio4BZuzIAXOwC7jgDIbMgQAnABzWZAEeOBWocATTYBOmgHSYA5NNknAAuOZAOiuAASZFdANQOAQCcALo5kCPLYBrxwBgtgAcnMQClR60ALpuF5QAHu8TMZC3FAEXbhTEBAUYNjaTlAH3HAGTrAFLGAfkxAECbAB1rAABq3QBiawBSm1UAICf5MQBVmwA-uzEBZRcASocAOpazMQAwhwBHmrQ0yytrMQA-awFOGzH9AC46mwA5u0P6BrT0jTGXAUvH5TEAWOsAHZsxAF57AG9HACcnMQFvl60BAicARccxAGVbMYUAUVrdAHEHMQBBJwAoPYAJ+pegBdVwA+o5hAAar-jqgERJvJNeSACKHyphfMlACpjW2MQmEdSSgAeRwAMdejAAnjgB+Jry7QAaq3VADOdgB8FzDhTBOeSAH07MIApBrqgGCal6Aa6HhLT-AzeXVAAG9gBDejyAAYXAA1jgAnO+WAATHAC5zgFWF+SAW1WJIAVeYkiuNgBIx+XKwAyixJADRLgBrOwAeKxqNYAeVcAJQvKwCjYxJABxromKgAP5wA3yxr5IALseKEjd8sU8sAI2uYQCYNWFhOjAC4T3lpgBcuzCAEdHALUzgByGzCAV5rAIw9B08dKqmEAlC3pTCAQcnAIgTAJBL0AvQOAUPHaeS6oANccANTUjRSm8WYfSARNGml1ADYLgAbOu4eLiARXGAphAN1d9MwgswgAWFwCDC4ANOeCEkw26cgBj2kY6Bu8AQicSZBTKFSACdHcRx6AB6ZhsajEAA3CAAA0IAQAADjATDoMgoDYAATghEAAO4AAqIQgaDICA2AADYodgACe2FgQARgh2BgAA1nAMAAMrYAAtnAAAyTBQHAyAAGb4WgcDkZRNF0fREFURxADmyAwAhACuAkgHATFkXADAMKprHYFAEmydgElwAAYhACFMdgMDQdpOHYLJMAQKBIAABYwExeEAOoOUw8BoGJYBwPRWGeawnlEThYBoKRIAcfxCEwGhlESaZPF8QpABWaAAB70ZJeFwAAirJEDwEleH8WBYkIdFOFkdgKl4fZEEIRxMCuUwDAwA5yAABwAAxlch-GuZREE4Q1cDRSwXFgQAjgV8BxZB2EoNgaAALScapqn2QhcAzUw21xXpiVILxJUKfxTFMNJclndleWzVxx3JWBMA1S1bUdUgABMz2UUweGSQAwhATFHYpaAAKz2bJ-EACo1YtJ2lSALDyQAklA6mwPRYCNVBACCGP0TARE5cV-EAL7k0AA
[dprint playground]: https://dprint.dev/playground/#code/MYewdgzgLgBAhjAvDAFASiQPlQKBjAHgBMBLAN0z3xkABmwStmZAdVcFtawFtHAdDpkBFRwFm6ZAFzsAu44AyGmIEAJwAc1MQBHjgVqHAE02ATpoB0MAOS9+awALjMQDorgAEm2NQDUDgEAnAC6MxAjy2Aa8cAYLYAHJmIClR3YAum1oMAD3Zw18tTkARdtYYQEBRpVVeAUAfccAZOsAUsYB+GEAQJsAHWsAAGotAGJrAFKbxQAgJxhhAFWbAD+6YQFlFwBKhwA6lmJhADCHAEeaZKQzs-JhAD9rAU4aYR0ALjpLADm73RqaZBRUYUcBS8cEYQBY6wAdmmEAXnsAb0cAJyZhAW+XdQECJwBFxmEAZVphWQBRWi0AcQZhAEEnAFB7ACfqzwBdVwB9RmEADVccCoBESYSJUEgAihzIweyhQAqYzNVCxWAUQoAHkcADHWQwAJ44AfiZs80AGqsFQAznYAfBZgnhgJkEgB9OmCAKQaCoBgmrOgGuh1j4xxE+kFQABvYAQ3qsgAGFwANY4AJzsFgAExwAuc4BVhcEgFtVriAFXmuMLVYASMcFosAMotcQA0S4AazsAHitSqWAHlXACULosAo2NcQAca+xUoAD+cAN8tSwSAC7HUlwLYLhILACNrMEAmDUeViQwAuE7Z8YAXLpggBHRwC1M4AchpggFeawCMPUtrAScjBAJQtkRggEHJwCIE083mdAL0DgFDx-GYgqADXHADU1bWE6s5MEUgETRko1QA2C4AGzoOVhogEVxpwwQDdXYSYMyYIAFhcAgwuADTnXFwYLOTIAY9raciL9CYbE40SEojEgAnR+FUAgAelIFBwaAA3EA/language/typescript
