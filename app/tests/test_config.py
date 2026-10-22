import pytest
from pydantic import ValidationError

from gateway_agent.config import Settings


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for name in ("BASE_URL", "API_KEY", "MODEL"):
        monkeypatch.delenv(f"GATEWAY_{name}", raising=False)


def _settings(**env: str) -> Settings:
    return Settings(_env_file=None, **env)


def test_loads_from_environment(monkeypatch):
    monkeypatch.setenv("GATEWAY_BASE_URL", "https://apim.azure-api.net/foundry/v1/")
    monkeypatch.setenv("GATEWAY_API_KEY", "k3y")
    settings = Settings(_env_file=None)
    assert settings.base_url == "https://apim.azure-api.net/foundry/v1"
    assert settings.api_key.get_secret_value() == "k3y"
    assert settings.model == "gpt-6-sol"


def test_secret_is_not_in_repr():
    settings = _settings(base_url="https://apim.azure-api.net/compass/v1", api_key="k3y")
    assert "k3y" not in repr(settings)


@pytest.mark.parametrize(
    "url",
    ["https://apim.azure-api.net/foundry", "apim.azure-api.net/foundry/v1"],
)
def test_rejects_bad_base_url(url):
    with pytest.raises(ValidationError):
        _settings(base_url=url, api_key="k3y")


def test_requires_key_and_url():
    with pytest.raises(ValidationError):
        _settings()
