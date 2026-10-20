"""LLM backends: Ollama (dev default), llama.cpp server (release), fake (tests)."""

from __future__ import annotations

from ..config import AppConfig
from .base import (
    GenParams,
    LLMBackend,
    LLMError,
    LLMResponseError,
    LLMTimeoutError,
    LLMUnavailableError,
)
from .fake import FakeBackend
from .llamacpp import LlamaCppBackend
from .ollama import OllamaBackend

__all__ = [
    "FakeBackend",
    "GenParams",
    "LLMBackend",
    "LLMError",
    "LLMResponseError",
    "LLMTimeoutError",
    "LLMUnavailableError",
    "LlamaCppBackend",
    "OllamaBackend",
    "create_backend",
]


def create_backend(cfg: AppConfig, kind: str, model: str) -> LLMBackend:
    if kind == "llamacpp":
        return LlamaCppBackend(model=model, base_url=cfg.llamacpp_url, read_timeout=cfg.llm_read_timeout)
    if kind == "ollama":
        return OllamaBackend(model=model, base_url=cfg.ollama_url, read_timeout=cfg.llm_read_timeout)
    raise ValueError(f"Unknown llm_backend: {kind}")
