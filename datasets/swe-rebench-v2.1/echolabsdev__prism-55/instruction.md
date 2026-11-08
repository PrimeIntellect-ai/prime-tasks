Grok text completions
Is it possible to use prism with xAI & Grok (not Groq)? It seems to be 'compatible' with OpenAI & Anthropic according to [the xAI documentation](https://docs.x.ai/api/integrations#openai-sdk).

```
import OpenAI from "openai";
const openai = new OpenAI({
  apiKey: "<api key>",
  baseURL: "https://api.x.ai/v1",
});

const completion = await openai.chat.completions.create({
  model: "grok-beta",
  messages: [
    { role: "system", content: "You are Grok, a chatbot inspired by the Hitchhiker's Guide to the Galaxy." },
    {
      role: "user",
      content: "What is the meaning of life, the universe, and everything?",
    },
  ],
});
```
I am confused how to do it though - I can't add another provider from the prism config file and I can't modify the existing provider to use the xAI server & API key.

### Additional contract requirements

- Applications can select the xAI provider using the public provider identifier `xai`.
- Configure its API key at `prism.providers.xai.api_key` (environment variable `XAI_API_KEY`) and its API endpoint at `prism.providers.xai.url` (environment variable `XAI_URL`). The default endpoint is `https://api.x.ai/v1`; these settings are separate from other providers.
