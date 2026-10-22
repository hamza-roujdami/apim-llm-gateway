from types import SimpleNamespace

from agent_framework import Content

from gateway_agent.streaming import delta_text


def _update(*contents: Content) -> SimpleNamespace:
    return SimpleNamespace(contents=list(contents))


def test_delta_is_printed():
    update = _update(Content.from_text(text="pong", merge_mode="append"))
    assert delta_text(update) == "pong"


def test_final_chunk_repeating_the_answer_is_skipped():
    update = _update(Content.from_text(text="pong pong", merge_mode="replace"))
    assert delta_text(update) == ""


def test_reasoning_and_empty_chunks_are_skipped():
    update = _update(Content.from_text_reasoning(text="thinking"), Content.from_text(text=""))
    assert delta_text(update) == ""
