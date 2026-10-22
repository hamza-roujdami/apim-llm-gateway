from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Gateway connection settings, read from GATEWAY_* environment variables or a .env file."""

    model_config = SettingsConfigDict(env_prefix="GATEWAY_", env_file=".env", extra="ignore")

    base_url: str = Field(
        description="Gateway base URL with the API prefix and /v1, "
        "e.g. https://<apim>.azure-api.net/foundry/v1 or .../compass/v1",
    )
    api_key: SecretStr = Field(description="APIM subscription key for that API.")
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
