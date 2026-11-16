add rule (rrd): component uses js and not ts
This should be only warning level and implement only when we have the cli options to filter out rules as this one might be quite controversal.

As I understand nuxt 4 might be defaults to ts, so `<script setup>` will mean ts.

### Additional contract requirements

- Add a public function `checkNoTsLang(script, filePath)` in `src/rules/rrd/noTsLang.ts` that records an offense when the script's `lang` is not `"ts"`.
- Add a public function `reportNoTsLang()` in `src/rules/rrd/noTsLang.ts` that returns the recorded offenses as an array of objects, each containing `file`, `rule`, `description` and `message`.
- Add a public function `resetResults()` in `src/rules/rrd/noTsLang.ts` that clears the recorded offenses.
- Analyzing a Vue component whose script does not use `lang="ts"` must report this rule's offense.
- For an offense reported when the script does not use `lang="ts"`:
  - `rule` must be exactly `<text_info>rrd ~ no ts lang</text_info>`
  - `description` must be exactly `👉 <text_warn>Use typescript instead of javascript.</text_warn> See: https://vue-mess-detector.webmania.cc/rules/rrd/no-ts-lang.html`
  - `message` must be exactly `<bg_warn>component uses js instead of ts</bg_warn> 🚨`
