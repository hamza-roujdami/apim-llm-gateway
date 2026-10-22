import re

from gateway_agent.tools import get_time, get_weather


def test_get_time_is_utc_timestamp():
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC", get_time())


def test_get_weather_known_city_is_case_insensitive():
    assert "sunny" in get_weather(" Dubai ")


def test_get_weather_unknown_city():
    assert "No demo weather data" in get_weather("Atlantis")
