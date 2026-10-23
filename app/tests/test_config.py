import pytest
from pydantic import ValidationError

from gateway_agent.config import Settings


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for name in ("BASE_URL", "AUTH", "API_KEY", "ENTRA_SCOPE", "MODEL"):
        monkeypatch.delenv(f"GATEWAY_{name}", raising=False)


def _settings(**env: str) -> Settings:
    return Settings(_env_file=None, **env)


def test_loads_from_environment(monkeypatch):
    monkeypatch.setenv("GATEWAY_BASE_URL", "https://apim.azure-api.net/foundry/v1/")
    monkeypatch.setenv("GATEWAY_API_KEY", "k3y")
    settings = Settings(_env_file=None)
    assert settings.base_url == "https://apim.azure-api.net/foundry/v1"
    assert settings.api_key.get_secret_value() == "k3y"
    assert settings.auth == "key"
    assert settings.model == "gpt-6-sol"


def test_secret_is_not_in_repr():
    settings = _settings(base_url="https://apim.azure-api.net/foundry/v1", api_key="k3y")
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


def test_entra_mode_needs_a_scope_not_a_key():
    settings = _settings(
        base_url="https://apim.azure-api.net/foundry/v1",
        auth="entra",
        entra_scope="api://abc/.default",
    )
    assert settings.api_key is None
    with pytest.raises(ValidationError):
        _settings(base_url="https://apim.azure-api.net/foundry/v1", auth="entra")


def test_key_mode_needs_a_key():
    with pytest.raises(ValidationError):
        _settings(base_url="https://apim.azure-api.net/foundry/v1", auth="key")
