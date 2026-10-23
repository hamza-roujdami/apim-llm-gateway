from contextlib import AsyncExitStack

from agent_framework import Agent, tool
from agent_framework.openai import OpenAIChatClient

from gateway_agent.config import Settings
from gateway_agent.tools import get_time, get_weather

INSTRUCTIONS = (
    "You are a concise assistant. Use the tools for the current time and for weather; "
    "do not guess either."
)


def build_client(settings: Settings, stack: AsyncExitStack | None = None) -> OpenAIChatClient:
    """The Responses client, authenticated the way the gateway is configured (key or Entra)."""
    if settings.auth == "entra":
        # Needs the "entra" extra. DefaultAzureCredential picks up a managed identity in Azure, or
        # the AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_CLIENT_SECRET variables elsewhere. The
        # token provider refreshes the token before it expires.
        from azure.identity.aio import DefaultAzureCredential, get_bearer_token_provider

        credential = DefaultAzureCredential()
        if stack is not None:
            stack.push_async_callback(credential.close)
        token_provider = get_bearer_token_provider(credential, settings.entra_scope)
        return OpenAIChatClient(
            model=settings.model, base_url=settings.base_url, api_key=token_provider
        )
    return OpenAIChatClient(
        model=settings.model,
        base_url=settings.base_url,
        # In key mode the gateway ignores the Bearer token the SDK sends from this value.
        api_key="unused",
        # The gateway authenticates the app with its APIM subscription key in "api-key".
        default_headers={"api-key": settings.api_key.get_secret_value()},
    )


def build_agent(settings: Settings, stack: AsyncExitStack | None = None) -> Agent:
    """Create an agent whose model calls go through the APIM gateway (Responses API).

    Pass an AsyncExitStack so the Entra credential is closed when the stack exits.
    """
    client = build_client(settings, stack)
    # approval_mode="never_require" is fine for these read-only demo tools. Use
    # "always_require" for tools with side effects.
    tools = [tool(approval_mode="never_require")(fn) for fn in (get_time, get_weather)]
    return Agent(client=client, name="GatewayAgent", instructions=INSTRUCTIONS, tools=tools)
