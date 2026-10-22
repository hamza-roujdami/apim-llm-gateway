def delta_text(update) -> str:
    """Return the text to print for one streamed agent update.

    The Responses stream sends text deltas (merge_mode "append") and then a final chunk that
    repeats the whole answer (merge_mode "replace"). Printing both would show the answer twice.
    """
    return "".join(
        content.text
        for content in update.contents
        if content.type == "text"
        and content.text
        and getattr(content, "merge_mode", "append") != "replace"
    )
