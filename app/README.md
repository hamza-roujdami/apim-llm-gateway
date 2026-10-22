# Gateway agent

A small [Microsoft Agent Framework](https://learn.microsoft.com/agent-framework/) agent that calls a model
through the APIM gateway, using the Responses API. It has two demo tools (current time, demo weather) so you
can see tool calling and streaming working through APIM.

It points at either API of the gateway; only the settings change:

| Backend | `GATEWAY_BASE_URL` | `GATEWAY_API_KEY` |
|---|---|---|
| Foundry | `https://<apim>.azure-api.net/foundry/v1` | `foundry-default` subscription key |
| Compass | `https://<apim>.azure-api.net/compass/v1` | `compass-default` subscription key |

## Run

Requires Python 3.13 and [uv](https://docs.astral.sh/uv/).

```bash
cd app
cp .env.example .env        # edit: base URL, subscription key, model
uv sync
uv run gateway-agent                                   # interactive chat
uv run gateway-agent "What's the weather in Dubai?"    # ask once
uv run gateway-agent --no-stream "What time is it?"
```

Get a subscription key with `az rest --method post --url ".../service/<apim>/subscriptions/foundry-default/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv`.

## How it connects

`src/gateway_agent/agent.py` builds an `OpenAIChatClient` with `base_url` set to the gateway and the
subscription key in the `api-key` header (`default_headers`). The SDK's own key is a dummy: the gateway
reads `api-key` and drops `Authorization` before calling the backend.

## Test

```bash
uv run pytest        # config, tools, and agent construction (no network)
uv run ruff check .
```

## Status

Run against the gateway (`/foundry`, `gpt-6-sol`) with `agent-framework-openai` 1.14.3 and
`agent-framework-core` 1.18.0: tool calls, streaming, non-streaming, multi-turn memory and error handling
work, and the 9 tests and `ruff` pass. The code was also checked against the 1.17.0 sources. The `/compass`
API is untested until a Compass key is available. `uv.lock` is not committed yet.
