AsyncInferenceClient model option for OpenAI's client does not work
### Describe the bug

In the AsyncInferenceClient it is written that if you want to use a custom openai base_url you have to use model instead of base_url

Extract from doc "Note: for better compatibility with OpenAI's client, model has been aliased as base_url. Those 2 arguments are mutually exclusive. If using base_url for chat completion, the /chat/completions suffix path will be appended to the base URL. When passing a URL as model, the client will not append any suffix path to it."

But when setting AsyncInferenceClient with model it still add /v1/chat/completion at the end of the endpoint when calling client. The error is still there even when trying to custom the  AsyncInferenceClient. [HIDDEN]



### Reproduction

from huggingface_hub import Agent

async def runAgent(data):

    # On récupère l'historique complet si fourni
    messages = data.get("messages")
    prompt = (data.get("prompt") or "").strip()

    async with Agent(
        model=data.get("model"),
        api_key=data.get("api_key"),
        servers=data.get("servers"),
    ) as agent:

        agent.client = AsyncInferenceClient(
            model= "https://url/deployments/gpt-4o/chat/completions?api-version=2024-06-01",
            api_key= str(AZURE_OPENAI_API_KEY)
        )
        await agent.load_tools()
        #print(agent.available_tools)
        response_acum = ""
        result = []

        try:
            async for chunk in agent.run(prompt):
                if hasattr(chunk, "choices"):
                    delta = chunk.choices[0].delta
                    if delta.content:
                        result.append(delta.content)
                        response_acum += delta.content
                    if delta.tool_calls:
                        for call in delta.tool_calls:
                            if call.function.name:
                                print(f"Calling Tool : {call.function.name} {call.function.arguments}\n")
        except Exception as e:
            tb_str = traceback.format_exc()
            print(f"\nError during agent run: {e}\n{tb_str}", flush=True)
        return result

if __name__ == "__main__":
    data = {
        "messages": [],
        "prompt": "Quel est la liste de tous les repos ?",
        "model": "https://url/deployments/gpt-4o/chat/completions?api-version=2024-06-01",
        "api_key": str(AZURE_OPENAI_API_KEY),
        "servers": [{"type": "http", "config": {"url": "http://localhost:9000/mcp"}}]
    }

    # Use asyncio.run for running the coroutine
    result = asyncio.run(runAgent(data))

### Logs

```shell
rror during agent run: 401, message='Access Denied', url='https://url/deployments/gpt-4o/chat/completions?api-version=2024-06-01/v1/chat/completions'
Traceback (most recent call last):
  File "/home/agents/tiny_agent_ju.py", line 89, in runAgent
    async for chunk in agent.run(prompt):
  File "/home/myenv/lib/python3.12/site-packages/huggingface_hub/inference/_mcp/agent.py", line 83, in run
    async for item in self.process_single_turn_with_tools(
  File "/home/myenv/lib/python3.12/site-packages/huggingface_hub/inference/_mcp/mcp_client.py", line 261, in process_single_turn_with_tools
    response = await self.client.chat.completions.create(
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/myenv/lib/python3.12/site-packages/huggingface_hub/inference/_generated/_async_client.py", line 964, in chat_completion
    data = await self._inner_post(request_parameters, stream=stream)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/myenv/lib/python3.12/site-packages/huggingface_hub/inference/_generated/_async_client.py", line 290, in _inner_post
    raise error
  File "/home/myenv/lib/python3.12/site-packages/huggingface_hub/inference/_generated/_async_client.py", line 276, in _inner_post
    response.raise_for_status()
  File "/home/myenv/lib/python3.12/site-packages/aiohttp/client_reqrep.py", line 629, in raise_for_status
    raise ClientResponseError(
aiohttp.client_exceptions.ClientResponseError: 401, message='Access Denied', url='https://url/deployments/gpt-4o/chat/completions?api-version=2024-06-01/v1/chat/completions'
```

### System info

```shell
- huggingface-hub[mcp]: 0.33.1
- Distribution : Ubuntu-22.04
- Python 3.12.3
```

### Additional contract requirements

- If a custom model URL already ends with `/chat/completions`, use it as the endpoint without adding another chat-completions path.
- If a custom model URL needs a chat-completions path, add that path before any query string and preserve the original query parameters.
