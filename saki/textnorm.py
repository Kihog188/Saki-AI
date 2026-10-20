"""Accent-insensitive text helpers for Vietnamese."""

from __future__ import annotations

import re
import unicodedata

_NON_WORD = re.compile(r"[^\w]+")


def fold(text: str) -> str:
    """Lowercase and strip Vietnamese diacritics: 'Giá Vàng' -> 'gia vang'."""
    text = text.replace("đ", "d").replace("Đ", "D")
    decomposed = unicodedata.normalize("NFD", text)
    stripped = "".join(c for c in decomposed if unicodedata.category(c) != "Mn")
    return stripped.casefold()


def fold_words(text: str) -> str:
    """Fold and collapse punctuation into single spaces."""
    return " ".join(_NON_WORD.sub(" ", fold(text)).split())
