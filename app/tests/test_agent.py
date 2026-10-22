from gateway_agent.agent import build_agent
from gateway_agent.config import Settings


def test_agent_builds_without_network():
    """Constructing the client and agent must not call the gateway."""
    settings = Settings(
        _env_file=None,
        base_url="https://apim.azure-api.net/foundry/v1",
        api_key="k3y",
    )
    agent = build_agent(settings)
    assert agent.name == "GatewayAgent"
