from agent_framework import Agent, tool
from agent_framework.openai import OpenAIChatClient

from gateway_agent.config import Settings
from gateway_agent.tools import get_time, get_weather

INSTRUCTIONS = (
    "You are a concise assistant. Use the tools for the current time and for weather; "
    "do not guess either."
)


def build_agent(settings: Settings) -> Agent:
    """Create an agent whose model calls go through the APIM gateway (Responses API)."""
    client = OpenAIChatClient(
        model=settings.model,
        base_url=settings.base_url,
        # The OpenAI SDK sends this as a Bearer token, which the gateway drops.
        api_key="unused",
        # The gateway authenticates the app with its APIM subscription key in "api-key".
        default_headers={"api-key": settings.api_key.get_secret_value()},
    )
    # approval_mode="never_require" is fine for these read-only demo tools. Use
    # "always_require" for tools with side effects.
    tools = [tool(approval_mode="never_require")(fn) for fn in (get_time, get_weather)]
    return Agent(client=client, name="GatewayAgent", instructions=INSTRUCTIONS, tools=tools)
