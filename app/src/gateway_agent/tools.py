"""Demo tools. Plain functions so they can be tested without the agent framework."""

from datetime import UTC, datetime
from typing import Annotated

from pydantic import Field

_DEMO_WEATHER = {
    "seattle": "rainy, 12°C",
    "dubai": "sunny, 36°C",
    "london": "cloudy, 14°C",
    "stockholm": "clear, 8°C",
}


def get_time() -> str:
    """Get the current UTC time."""
    return datetime.now(UTC).strftime("%Y-%m-%d %H:%M:%S UTC")


def get_weather(
    location: Annotated[str, Field(description="City name, e.g. Dubai.")],
) -> str:
    """Get the current weather for a city. Demo data, not a real forecast."""
    conditions = _DEMO_WEATHER.get(location.strip().lower())
    if conditions is None:
        return f"No demo weather data for {location}."
    return f"The weather in {location} is {conditions}."
