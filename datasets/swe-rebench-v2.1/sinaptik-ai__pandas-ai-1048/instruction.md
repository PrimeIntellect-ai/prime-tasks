NameError: name 'data' is not defined
### System Info

MarkupSafe-2.1.5 annotated-types-0.6.0 anyio-4.3.0 astor-0.8.1 certifi-2024.2.2 charset-normalizer-3.3.2 colorama-0.4.6 contourpy-1.2.0 cycler-0.12.1 distro-1.9.0 duckdb-0.10.0 exceptiongroup-1.2.0 faker-19.13.0 fonttools-4.50.0 greenlet-3.0.3 h11-0.14.0 httpcore-1.0.4 httpx-0.27.0 idna-3.6 jinja2-3.1.3 kiwisolver-1.4.5 matplotlib-3.8.3 numpy-1.26.4 openai-1.14.1 packaging-24.0 pandas-1.5.3 **_### pandasai-2.0.16_** pillow-10.2.0 pydantic-2.6.4 pydantic-core-2.16.3 pyparsing-3.1.2 python-dateutil-2.9.0.post0 python-dotenv-1.0.1 pytz-2024.1 requests-2.31.0 scipy-1.12.0 six-1.16.0 sniffio-1.3.1 sqlalchemy-2.0.28 tqdm-4.66.2 typing-extensions-4.10.0 urllib3-2.2.1

### 🐛 Describe the bug

## i simply run the sample code below

import pandas as pd
from pandasai import SmartDataframe

# Sample DataFrame
sales_by_country = pd.DataFrame({
    "country": ["United States", "United Kingdom", "France", "Germany", "Italy", "Spain", "Canada", "Australia", "Japan", "China"],
    "sales": [5000, 3200, 2900, 4100, 2300, 2100, 2500, 2600, 4500, 7000]
})

# Instantiate a LLM
from pandasai.llm import OpenAI
llm = OpenAI(api_token="YOUR_API_TOKEN")

df = SmartDataframe(sales_by_country, config={"llm": llm})
df.chat('Which are the top 5 countries by sales?')   ## generate the correct anwer


df.chat(    "What is the total sales for the top 3 countries by sales?"  )  ## generate the error below:

--------------
>>> df
<pandasai.smart_dataframe.SmartDataframe object at 0x0000023B2281A650>
>>> df.chat(
...     "What is the total sales for the top 3 countries by sales?"
... )
Traceback (most recent call last):
  File "F:\envs\lenono\lib\site-packages\pandasai\pipelines\chat\generate_chat_pipeline.py", line 281, in run
    output = (self.code_generation_pipeline | self.code_execution_pipeline).run(
  File "F:\envs\lenono\lib\site-packages\pandasai\pipelines\pipeline.py", line 137, in run
    raise e
  File "F:\envs\lenono\lib\site-packages\pandasai\pipelines\pipeline.py", line 101, in run
    step_output = logic.execute(
  File "F:\envs\lenono\lib\site-packages\pandasai\pipelines\chat\code_execution.py", line 93, in execute
    raise e
  File "F:\envs\lenono\lib\site-packages\pandasai\pipelines\chat\code_execution.py", line 64, in execute
    result = code_manager.execute_code(code_to_run, code_context)
  File "F:\envs\lenono\lib\site-packages\pandasai\helpers\code_manager.py", line 181, in execute_code
    code_to_run = self._clean_code(code, context)
  [HIDDEN]
  File "<ast>", line 3, in <module>
NameError: name 'data' is not defined
"Unfortunately, I was not able to answer your question, because of the following error:\n\nname 'data' is not defined\n"

### Additional contract requirements

- In the reported two-step `SmartDataframe` interaction, the follow-up request for total sales of the top three countries must produce a response rather than fail with `NameError` when the generated DataFrame construction uses a variable assigned earlier.
