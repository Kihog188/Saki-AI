from saki.hardware import LOW_RAM_WARNING, recommend_tier


def test_tiers():
    low = recommend_tier(0.8)
    assert low.tier == "insufficient" and low.warning == LOW_RAM_WARNING
    small = recommend_tier(1.8)
    assert small.tier == "small" and small.warning is None
    std = recommend_tier(4.0)
    assert std.tier == "standard"
    assert std.to_dict()["free_ram_gb"] == 4.0


def test_reads_real_ram():
    rec = recommend_tier()
    assert rec.free_ram_gb > 0
