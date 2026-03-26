# TICKET-005: Integration Tests — Python OpenAI Client E2E

**Status:** Open
**Priority:** P1 (validation of OpenAI compatibility goal)
**Blocked by:** TICKET-003, TICKET-004 (CLI + server polish needed first)

---

## Goal

A Python test suite using the `openai` library that validates all major features
of the apfel OpenAI-compatible server against the actual running binary.

## Test File Location

`Tests/integration/openai_client_test.py`

## Tests to Implement

```python
import openai
client = openai.OpenAI(base_url="http://localhost:11434/v1", api_key="ignored")

def test_basic_completion():
    resp = client.chat.completions.create(
        model="apple/on-device-3b",
        messages=[{"role": "user", "content": "What is 2+2? Reply with just the number."}]
    )
    assert "4" in resp.choices[0].message.content

def test_streaming():
    stream = client.chat.completions.create(
        model="apple/on-device-3b",
        messages=[{"role": "user", "content": "Say hello"}],
        stream=True
    )
    content = "".join(chunk.choices[0].delta.content or "" for chunk in stream)
    assert len(content) > 0

def test_multi_turn_history():
    messages = [
        {"role": "user", "content": "My name is TestUser."},
        {"role": "assistant", "content": "Hello TestUser!"},
        {"role": "user", "content": "What is my name?"}
    ]
    resp = client.chat.completions.create(model="apple/on-device-3b", messages=messages)
    assert "TestUser" in resp.choices[0].message.content

def test_temperature_zero():
    # Two identical requests with temperature=0 and same seed should give same result
    kwargs = dict(model="apple/on-device-3b",
                  messages=[{"role": "user", "content": "What is 2+2?"}],
                  temperature=0, seed=42)
    r1 = client.chat.completions.create(**kwargs)
    r2 = client.chat.completions.create(**kwargs)
    assert r1.choices[0].message.content == r2.choices[0].message.content

def test_tool_calling():
    tools = [{
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get weather for a city",
            "parameters": {
                "type": "object",
                "properties": {"city": {"type": "string"}},
                "required": ["city"]
            }
        }
    }]
    resp = client.chat.completions.create(
        model="apple/on-device-3b",
        messages=[{"role": "user", "content": "What's the weather in Vienna?"}],
        tools=tools
    )
    assert resp.choices[0].finish_reason == "tool_calls"
    assert resp.choices[0].message.tool_calls[0].function.name == "get_weather"

def test_models_endpoint():
    models = client.models.list()
    assert len(models.data) > 0
    assert models.data[0].id == "apple/on-device-3b"

def test_image_rejection():
    try:
        client.chat.completions.create(
            model="apple/on-device-3b",
            messages=[{"role": "user", "content": [
                {"type": "text", "text": "What's in this image?"},
                {"type": "image_url", "image_url": {"url": "http://example.com/img.jpg"}}
            ]}]
        )
        assert False, "Should have raised"
    except openai.BadRequestError as e:
        assert "image" in str(e).lower()
```

## Running

```bash
pip install openai pytest
.build/release/apfel --serve --port 11434 &
SERVER_PID=$!
python3 -m pytest Tests/integration/openai_client_test.py -v
kill $SERVER_PID
```
