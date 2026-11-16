Support Thunderstorm and Next-Week Properties in Simplified Chinese
In the near future, the API will begin generating the following new properties:

*   `possible-thunderstorm`
*   `thunderstorm`
*   `next-sunday`
*   `next-monday`
*   `next-tuesday`
*   `next-wednesday`
*   `next-thursday`
*   `next-friday`
*   `next-saturday`

Add support for these properties to simplified Chinese. (Information is available in the README, and examples are visible in `/lib/lang/en.js` and `/test_cases/en.js`.)

### Additional contract requirements

- The following translations must produce these exact outputs: `["title",["and","medium-clouds","possible-thunderstorm"]]` → `多云，可能有雷暴`; `["title",["and","medium-clouds","thunderstorm"]]` → `多云，雷暴`; and `["sentence",["until","thunderstorm","next-monday"]]` → `雷暴将持续至下周一。`
- The following next-week translations must produce these exact outputs: `["title","next-sunday"]` → `下周日`; `["title","next-tuesday"]` → `下周二`; `["title","next-wednesday"]` → `下周三`; `["title","next-thursday"]` → `下周四`; `["title","next-friday"]` → `下周五`; and `["title","next-saturday"]` → `下周六`.
