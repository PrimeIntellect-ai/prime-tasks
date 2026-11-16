Unfortunately, I was not able to get your answers, because of the following error:\n\n'NoneType' object has no attribute 'type'\n
### System Info

windows 10,
python 3.9.5


### 🐛 Describe the bug

I run this default code, but get error
"Unfortunately, I was not able to get your answers, because of the following error:\n\n'NoneType' object has no attribute 'type'\n"

I did something wrong? what should I do?

thanks

```
import os
import pandas as pd
from pandasai import SmartDataframe

sales_by_country = pd.DataFrame({
    "country": ["United States", "United Kingdom", "France", "Germany", "Italy", "Spain", "Canada", "Australia", "Japan", "China"],
    "sales": [5000, 3200, 2900, 4100, 2300, 2100, 2500, 2600, 4500, 7000]
})

# I get my API key from https://www.pandabi.ai/admin/api-keys, it's free? this API can provide LLM function?
# I replaced YOUR_API_KEY by API_key from https://www.pandabi.ai/admin/api-keys
os.environ["PANDASAI_API_KEY"] = "YOUR_API_KEY"

agent = SmartDataframe(sales_by_country)
agent.chat('Which are the top 5 countries by sales?')
```

### Additional contract requirements

- `Config` is a public class in the module `pandasai.schemas.df_config`. Its `llm` attribute is an instance of `pandasai.llm.bamboo_llm.BambooLLM` whenever no `llm` is supplied and whenever `None` is supplied as `llm`.
- When an `LLM` instance (including a `LangchainLLM`) is supplied as `llm`, that same instance is kept as `Config.llm`.
