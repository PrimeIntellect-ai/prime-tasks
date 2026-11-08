[Bug] Google Models do not stream chunks using StreamListener
### What happened?

Streaming individual chunks doesn't work for several if not all Google models including Flash 2.0, 2.5, and Gemma 3. I also couldn't get Grok 3 mini to do it either, but that may be because it was a thinking model? Not sure.

I debugged the problem and the root cause is because of the way chunks are tokenized and transmitted.

Here's how they look like for Google models. Assume each line is a chunk:

```
[
[ ## sum
mary ## ]]\nOnce upon a
```

So you'll see that it doesn't cleanly start with `[[` nor does it end cleanly with `]]\n`.

I tried a variety of other models and most of them work with the current implementation: Mistral Small 3.1 24b, Llama 4 Scout, and Llama 3.3.

### Steps to reproduce

Use any Google model in openrouter

```python
dspy.LM(model="openrouter/google/gemma-3-12b-it", cache=False)
```

Set up streaming with a `StreamListener`.

```python
streaming_summary = streamify(
        Summary,
        stream_listeners=[StreamListener(signature_field_name="summary")]
    )
```

```python
stream = streaming_summary(article=article)
        async for chunk in stream:
            if isinstance(chunk, StreamResponse):
                output += chunk.chunk
                print(chunk.chunk, end="", flush=True)
```

#### Full Example

```python
import os
import dspy
from dotenv import load_dotenv
import asyncio
from dspy.streaming import streamify, StreamListener, StreamResponse

# Load environment variables from .env file
load_dotenv()

# Configure DSPy to use OpenRouter
openrouter_api_key = os.getenv("OPENROUTER_API_KEY")
if openrouter_api_key:
    # Use OpenRouter if API key is available
    lm = dspy.LM(model="openrouter/google/gemma-3-12b-it", cache=False) # doesnt work
else:
    # Fallback to local model
    print("OpenRouter API key not found. Using local model.")
    lm = dspy.LM('ollama_chat/gemma3:12b-it-qat', api_base='http://localhost:11434', api_key='')

# Set the language model
dspy.settings.configure(lm=lm, adapter=dspy.JSONAdapter())

# --- Article Summarizer Implementation ---

class ArticleSummarizerSignature(dspy.Signature):
    """
    You are an expert summarizer. Your task is to create a concise, informative summary of the provided article.

    The summary should:
    1. Capture the main points and key information
    2. Maintain the original meaning and intent
    3. Be significantly shorter than the original text
    4. Be written in clear, professional language
    5. Include the most important facts, findings, or arguments

    Article to summarize:
    {article_text}

    ---
    Summary:
    """
    article_text: str = dspy.InputField(desc="The full text of the article to be summarized.")
    summary: str = dspy.OutputField(desc="A one sentence summary of the article that captures the main points.")

class ArticleSummarizer(dspy.Module):
    def __init__(self):
        super().__init__()
        self.summarizer = dspy.Predict(ArticleSummarizerSignature)

    def forward(self, article: str):
        prediction = self.summarizer(
            article_text=article
        )
        return prediction


if __name__ == "__main__":
    summarizer = ArticleSummarizer()
    # Stream only the 'summary' output field
    streaming_summarizer = streamify(
        summarizer,
        stream_listeners=[StreamListener(signature_field_name="summary")],
        include_final_prediction_in_output_stream=False
    )

    async def main():
        print("\nArticle Summarizer (Streaming)\n----------------------")

        article = """
        Jack Clark, cofounder of Anthropic, predicts the rise of “manager nerds” as AI agents increasingly take over tasks traditionally done by humans. Speaking on the “Conversations With Tyler” podcast, Clark explained that future managers will orchestrate fleets of AI agents rather than direct people, potentially making small teams extremely powerful. He noted startups are already operating effectively with fewer employees due to AI coding agents. Industry leaders, including Meta CEO Mark Zuckerberg and Y Combinator CEO Garry Tan, echoed this sentiment, highlighting how AI enables lean, highly skilled teams to reach significant revenue milestones. Krieger, Instagram cofounder and Anthropic’s chief product officer, suggested developers will shift from writing code to managing and reviewing AI-generated content. However, experts caution that overreliance on AI carries risks, such as hallucinations from large language models and difficulties scaling or debugging AI-generated code. Anthropic positions itself as a testbed for adapting to AI-driven workplace changes, emphasizing AI’s role in collaboration rather than replacement.
        """

        if not article.strip():
            print("No article provided. Exiting.")
            return

        print("\nStreaming generated summary...\n")
        output = ""
        stream = streaming_summarizer(article=article)
        async for chunk in stream:
            if isinstance(chunk, StreamResponse):
                output += chunk.chunk
                print(chunk.chunk, end="", flush=True)
            elif isinstance(chunk, dspy.Prediction):
                print(chunk.summary, end="", flush=True)
        print("\n\n[Streaming complete]")

    asyncio.run(main())

```

### DSPy version

2.6.23

### Additional contract requirements

- StreamListener must extract and stream the selected field's text when provider deltas split or combine adapter framing, without including that framing in the field text. The resulting text must not depend on the provider's chunk boundaries.
- For ChatAdapter streaming of an `answer` field, when the remaining answer text arrives as the provider deltas `" side"`, `" of"`, `" the"`, `" dinner"`, `" plate"`, and `"!"`, emit that remaining text as a single `StreamResponse` whose `chunk` is `" side of the dinner plate!"`.
