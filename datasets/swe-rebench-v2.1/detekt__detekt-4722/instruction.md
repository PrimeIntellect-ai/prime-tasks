OptionalWhenBraces false negative
Copied from https://github.com/detekt/detekt/issues/4245#issuecomment-1098366683

Issue is present in 1.19 and 1.20

```
import android.icu.text.PluralRules
import kotlinx.serialization.json.JsonObject
import java.util.Locale

fun JsonObject.plural(
  plural: Number?,
  language: String = "en"
) = when(plural) {
  null -> get("other")

  else -> {
    when {
      "other" in this -> get(
        PluralRules.forLocale(
          Locale.forLanguageTag(language)
        ).toString()
      )

      // other must be present even if a present rule would match
      else -> null
    }
  }
}
```
