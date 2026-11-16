error logging lines are unreachable and `e` is unbound
### 🐛 Describe the bug

In `mem0/memory/main.py` error logging lines are unreachable and `e` is unbound for
`AsyncMemory._add_to_vector_store`
```
logging.error(f"Error in new_retrieved_facts: {e}")
```
and
```
logging.error(f"Invalid JSON response: {e}")
```

### Additional contract requirements

- `AsyncMemory._add_to_vector_store(self, messages: List[Dict[str, Any]], metadata: Dict[str, Any], effective_filters: Dict[str, Any], infer: bool) -> List[Dict[str, Any]]` is defined in `mem0/memory/main.py` and accepts the filter set as the `effective_filters` argument.
- When the fact-extraction response is empty or cannot be parsed, the method logs an error containing `Error in new_retrieved_facts` and returns an empty list.
- When the memory-actions response is empty or cannot be parsed, the method logs an error containing `Invalid JSON response` and returns an empty list.
- The method records a telemetry event by calling `capture_event(event_name, memory_instance, details)` from `mem0.memory.telemetry` (available as `mem0.memory.main.capture_event`).
