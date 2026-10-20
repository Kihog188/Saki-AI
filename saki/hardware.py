"""Free-RAM check and model tier recommendation (report only)."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

import psutil

LOW_RAM_GB = 1.2
STANDARD_RAM_GB = 2.5

LOW_RAM_WARNING = "Máy đang thiếu RAM, hãy đóng bớt ứng dụng"


@dataclass(frozen=True)
class TierRecommendation:
    free_ram_gb: float
    tier: str  # "insufficient" | "small" | "standard"
    model_hint: str
    warning: str | None

    def to_dict(self) -> dict:
        return {
            "free_ram_gb": round(self.free_ram_gb, 2),
            "tier": self.tier,
            "model_hint": self.model_hint,
            "warning": self.warning,
        }


def free_ram_gb() -> float:
    return psutil.virtual_memory().available / (1024**3)


def recommend_tier(free_gb: float | None = None) -> TierRecommendation:
    """Recommend a model tier from free RAM. The model itself is chosen in config."""
    gb = free_ram_gb() if free_gb is None else free_gb
    if gb < LOW_RAM_GB:
        return TierRecommendation(gb, "insufficient", "qwen2.5-0.5b", LOW_RAM_WARNING)
    if gb < STANDARD_RAM_GB:
        return TierRecommendation(gb, "small", "qwen2.5-0.5b", None)
    return TierRecommendation(gb, "standard", "qwen2.5-1.5b", None)


class ModelProvisioner(ABC):
    """Interface for fetching model files on first run.

    TODO: implement auto-download of GGUF files for the recommended tier
    (checksum verification, resumable downloads, progress events for the frontend).
    Not part of the MVP: models are installed manually and selected in config.
    """

    @abstractmethod
    def is_installed(self, tier: str) -> bool: ...

    @abstractmethod
    async def ensure_model(self, tier: str) -> str:
        """Make sure the model for `tier` is available; return its name or path."""
