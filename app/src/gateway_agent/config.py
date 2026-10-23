from typing import Literal

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Gateway connection settings, read from GATEWAY_* environment variables or a .env file."""

    model_config = SettingsConfigDict(env_prefix="GATEWAY_", env_file=".env", extra="ignore")

    base_url: str = Field(
        description="Gateway base URL with the API prefix and /v1, "
        "e.g. https://<apim>.azure-api.net/foundry/v1",
    )
    auth: Literal["key", "entra"] = Field(
        default="key",
        description="key: APIM subscription key. entra: an Entra ID token (authMode=entra).",
    )
    api_key: SecretStr | None = Field(default=None, description="APIM subscription key (key mode).")
    entra_scope: str | None = Field(
        default=None,
        description="Entra token scope (auth=entra), e.g. api://<gateway-client-id>/.default.",
    )
    model: str = Field(default="gpt-6-sol", description="Model or deployment name.")

    @field_validator("base_url")
    @classmethod
    def _normalise_base_url(cls, value: str) -> str:
        value = value.strip().rstrip("/")
        if not value.startswith(("https://", "http://")):
            raise ValueError("must start with https://")
        # The OpenAI client appends /responses to the base URL.
        if not value.endswith("/v1"):
            raise ValueError("must end with /v1, e.g. https://<apim>.azure-api.net/foundry/v1")
        return value

    @model_validator(mode="after")
    def _require_credentials_for_auth_mode(self) -> "Settings":
        if self.auth == "key" and self.api_key is None:
            raise ValueError("GATEWAY_API_KEY is required when GATEWAY_AUTH=key")
        if self.auth == "entra" and not self.entra_scope:
            raise ValueError("GATEWAY_ENTRA_SCOPE is required when GATEWAY_AUTH=entra")
        return self
