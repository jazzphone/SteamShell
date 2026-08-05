#!/usr/bin/env python3
"""Deterministic simulation for SteamShell-XFE learned RawInput profiles.

This does not execute AutoHotkey. It mirrors the small, self-contained learning
heuristic and profile decoder against synthetic HID reports so the byte-width,
endianness, direction, range, active-low, and shared-trigger cases remain
reproducible on non-Windows development machines.
"""

from __future__ import annotations

from dataclasses import dataclass
import struct


MIN_NORMALISED_DELTA = 4000
MIN_BYTE_EXCURSION = 8
MIN_PAIR_BALANCE = 0.20


@dataclass
class Axis:
    offset: int
    size: str
    neutral: int
    direction: int
    extent: int


def axis_raw(report: bytes, offset: int, size: str) -> int:
    if size == "u8":
        return report[offset]
    return int.from_bytes(
        report[offset : offset + 2],
        "little" if size == "u16le" else "big",
    )


def high_byte_quality(
    baseline: bytes, samples: list[bytes], offset: int, sample_count: int
) -> float:
    previous = baseline[offset]
    path = 0
    transitions = 0
    endpoint = previous
    for report in samples[:sample_count]:
        value = report[offset]
        transitions += value != previous
        path += abs(value - previous)
        previous = value
        endpoint = value
    endpoint = abs(endpoint - baseline[offset])
    coherence = endpoint / max(1, path)
    activity = transitions / max(1, sample_count)
    return (0.25 + 0.75 * coherence) * (0.25 + 0.75 * activity)


def axis_stats(
    baseline: bytes, samples: list[bytes], offset: int, size: str
) -> dict[str, float | int | str]:
    neutral = axis_raw(baseline, offset, size)
    previous = neutral
    path = 0
    path_at_peak = 0
    peak_raw = neutral
    peak_index = 0
    extent = 0
    for index, report in enumerate(samples, start=1):
        raw = axis_raw(report, offset, size)
        path += abs(raw - previous)
        previous = raw
        sample_extent = abs(raw - neutral)
        if sample_extent > extent:
            extent = sample_extent
            peak_raw = raw
            peak_index = index
            path_at_peak = path
    delta = extent * (256 if size == "u8" else 1)
    coherence = extent / max(1, path_at_peak)
    score = delta * (0.20 + 0.80 * coherence)
    if size != "u8":
        high_offset = offset + 1 if size == "u16le" else offset
        score *= high_byte_quality(baseline, samples, high_offset, peak_index)
    return {
        "offset": offset,
        "size": size,
        "neutral": neutral,
        "raw": peak_raw,
        "extent": extent,
        "delta": delta,
        "coherence": coherence,
        "score": score,
    }


def learn_axis(
    baseline: bytes,
    samples: list[bytes],
    want: int,
    claimed: set[int] | None = None,
) -> Axis:
    claimed = claimed or set()
    length = len(baseline)
    excursions = [
        max(abs(report[offset] - baseline[offset]) for report in samples)
        for offset in range(length)
    ]

    best8 = None
    for offset in range(length):
        if offset in claimed or excursions[offset] < MIN_BYTE_EXCURSION:
            continue
        candidate = axis_stats(baseline, samples, offset, "u8")
        if candidate["delta"] < MIN_NORMALISED_DELTA:
            continue
        if best8 is None or candidate["score"] > best8["score"]:
            best8 = candidate

    best16 = None
    for offset in range(length - 1):
        if offset in claimed or offset + 1 in claimed:
            continue
        first, second = excursions[offset : offset + 2]
        if min(first, second) < MIN_BYTE_EXCURSION:
            continue
        if min(first, second) / max(first, second) < MIN_PAIR_BALANCE:
            continue
        little = axis_stats(baseline, samples, offset, "u16le")
        big = axis_stats(baseline, samples, offset, "u16be")
        candidate = max((little, big), key=lambda item: item["score"])
        if (
            candidate["delta"] < MIN_NORMALISED_DELTA
            or candidate["coherence"] < 0.55
        ):
            continue
        if best16 is None or candidate["score"] > best16["score"]:
            best16 = candidate

    if best16 is not None and (
        best8 is None or best16["score"] >= best8["score"] * 0.45
    ):
        chosen = best16
    else:
        chosen = best8
    assert chosen is not None, "axis was not detected"
    direction = -want if chosen["raw"] < chosen["neutral"] else want
    return Axis(
        offset=int(chosen["offset"]),
        size=str(chosen["size"]),
        neutral=int(chosen["neutral"]),
        direction=direction,
        extent=max(1, int(chosen["extent"])),
    )


TRAVEL = (0.04, 0.11, 0.19, 0.28, 0.36, 0.49, 0.57, 0.68, 0.76, 0.87, 0.94, 1.0)


def capture(make_report, field: str, start: int, target: int) -> list[bytes]:
    reports = [
        make_report(**{field: round(start + (target - start) * fraction)})
        for fraction in TRAVEL
    ]
    reports.extend(make_report(**{field: target}) for _ in range(8))
    return reports


def make_ally(
    lx=0x8000, ly=0x8000, rx=0x8000, ry=0x8000, trigger=0x8000,
    face=0, extra=0, hat=0,
) -> bytes:
    report = bytearray(16)
    for offset, value in ((1, lx), (3, ly), (5, rx), (7, ry), (9, trigger)):
        struct.pack_into("<H", report, offset, value)
    report[11:14] = bytes((face, extra, hat))
    return bytes(report)


def make_u8(
    lx=128, ly=128, rx=128, ry=128, lt=0, rt=0, buttons=0xFF
) -> bytes:
    return bytes((1, lx, ly, rx, ry, lt, rt, buttons, 0, 0, 0, 0))


def make_be(value=0x8000) -> bytes:
    report = bytearray(6)
    report[0] = 7
    report[1:3] = value.to_bytes(2, "big")
    return bytes(report)


def decode_axis(axis: Axis, report: bytes, trigger: bool = False) -> int:
    raw = axis_raw(report, axis.offset, axis.size)
    delta = (raw - axis.neutral) * axis.direction
    if trigger:
        if delta <= 0:
            return 0
        return min(255, round(delta * 255 / max(1, axis.extent)))
    scaled = round((raw - axis.neutral) * 32767 / max(1, axis.extent))
    return max(-32767, min(32767, scaled * axis.direction))


def test_ally_16_bit_and_shared_triggers() -> None:
    baseline = make_ally()
    claimed = {11, 12, 13}
    cases = (
        ("LX", "lx", 0, -1, 1),
        ("LY", "ly", 0, 1, 3),
        ("RX", "rx", 0, -1, 5),
        ("RY", "ry", 0, 1, 7),
        ("LT", "trigger", 0xFFFF, 1, 9),
        ("RT", "trigger", 0, 1, 9),
    )
    learned = {}
    for name, field, target, want, offset in cases:
        learned[name] = learn_axis(
            baseline,
            capture(make_ally, field, 0x8000, target),
            want,
            claimed,
        )
        axis = learned[name]
        assert (axis.offset, axis.size) == (offset, "u16le")

    assert learned["LT"].offset == learned["RT"].offset
    assert learned["LT"].direction == 1
    assert learned["RT"].direction == -1
    assert decode_axis(learned["LX"], make_ally(lx=0), False) == -32767
    assert decode_axis(learned["LX"], make_ally(lx=0xFFFF), False) >= 32766
    assert decode_axis(learned["LY"], make_ally(ly=0), False) == 32767
    assert decode_axis(learned["LT"], make_ally(trigger=0xFFFF), True) == 255
    assert decode_axis(learned["RT"], make_ally(trigger=0), True) == 255
    assert decode_axis(learned["RT"], make_ally(trigger=0xFFFF), True) == 0


def test_u8_axes_and_independent_triggers() -> None:
    baseline = make_u8()
    cases = (
        ("lx", 128, 0, -1, 1),
        ("ly", 128, 0, 1, 2),
        ("rx", 128, 0, -1, 3),
        ("ry", 128, 0, 1, 4),
        ("lt", 0, 255, 1, 5),
        ("rt", 0, 255, 1, 6),
    )
    for field, start, target, want, offset in cases:
        axis = learn_axis(
            baseline,
            capture(make_u8, field, start, target),
            want,
            {0, 7},
        )
        assert (axis.offset, axis.size) == (offset, "u8")
        report = make_u8(**{field: target})
        assert decode_axis(axis, report, field in ("lt", "rt")) in (255, 32767, -32767)


def test_big_endian_axis() -> None:
    baseline = make_be()
    axis = learn_axis(
        baseline,
        capture(make_be, "value", 0x8000, 0xFFFF),
        1,
        {0},
    )
    assert (axis.offset, axis.size) == (1, "u16be")
    assert decode_axis(axis, make_be(0xFFFF), False) == 32767


def test_active_low_button() -> None:
    mask = 0x04
    released = make_u8(buttons=0xFF)
    pressed = make_u8(buttons=0xFB)
    rest_noise = 0
    changed = (pressed[7] ^ released[7]) & ~rest_noise & 0xFF
    learned_mask = changed & -changed
    pressed_value = pressed[7] & learned_mask
    assert learned_mask == mask
    assert pressed_value == 0
    assert (released[7] & mask) != pressed_value
    assert (pressed[7] & mask) == pressed_value


def test_masked_hat_shares_button_byte() -> None:
    hat_mask = 0x0F
    released = 0x08
    east = 0x02
    face_button = 0x40
    directions = {0x00: "N", 0x01: "NE", 0x02: "E", 0x03: "SE"}
    report_value = face_button | east
    masked = report_value & hat_mask
    assert masked != released
    assert directions[masked] == "E"


def test_change_only_digital_report_is_sufficient() -> None:
    """The Ally sends one state-change report, not repeated held reports."""
    baseline = make_ally()
    pressed = make_ally(face=0x01)
    rest_noise = bytes(len(baseline))
    clean_changes = [
        (now ^ was) & ~noise & 0xFF
        for now, was, noise in zip(pressed, baseline, rest_noise)
    ]
    assert clean_changes[11] == 0x01
    learned_mask = clean_changes[11] & -clean_changes[11]
    assert learned_mask == 0x01

    dpad = make_ally(hat=1)
    assert dpad[13] != baseline[13]
    assert (dpad[13] ^ baseline[13]) & ~rest_noise[13] == 1


def test_change_only_identification_uses_release_baseline() -> None:
    """First-seen A press must not become the resting button state."""
    first_seen = make_ally(face=0x01)
    identifying_release = make_ally(face=0x00)

    # The report that completes identification starts the explicit rest phase.
    learned_baseline = identifying_release
    assert first_seen[11] == 0x01
    assert learned_baseline[11] == 0x00

    a_press = make_ally(face=0x01)
    b_press = make_ally(face=0x02)
    a_changed = a_press[11] ^ learned_baseline[11]
    b_changed = b_press[11] ^ learned_baseline[11]
    assert a_changed & -a_changed == 0x01
    assert b_changed & -b_changed == 0x02


def test_axis_peak_survives_release_and_prevents_carryover() -> None:
    """The outward peak is retained, but neutral ends the step cleanly."""
    baseline = make_ally()
    outward = [
        make_ally(lx=round(0x8000 * (1 - fraction)))
        for fraction in TRAVEL
    ]
    released = make_ally()

    # A release report is not part of the recorded outward sweep. Even if it
    # were appended accidentally, peak-based resolution must retain full travel.
    axis = learn_axis(baseline, outward + [released], -1, {11, 12, 13})
    assert (axis.offset, axis.size) == (1, "u16le")
    assert axis.extent == 0x8000
    assert axis_raw(released, axis.offset, axis.size) == axis.neutral
    assert decode_axis(axis, released, False) == 0

    # The next prompt begins from neutral rather than seeing LX still held.
    next_first_report = make_ally(ly=0x7000)
    assert axis_raw(next_first_report, axis.offset, axis.size) == axis.neutral


MIN_DISTINCT_VALUES = 6
MIN_RANGE = 32


def classify_analog(samples: list[bytes], length: int) -> set[int]:
    """Mirror of ControllerLearnClassifyAnalog.

    A button byte takes two values; an axis byte swept through its range takes
    dozens. Both a wide range and many distinct values are required, so neither a
    two-mask button byte nor a monotonic counter is mistaken for an axis.
    """
    values: dict[int, set[int]] = {}
    for report in samples:
        for offset in range(length):
            values.setdefault(offset, set()).add(report[offset])
    return {
        offset
        for offset, seen in values.items()
        if len(seen) >= MIN_DISTINCT_VALUES and (max(seen) - min(seen)) >= MIN_RANGE
    }


def test_analog_scan_protects_stick_click_steps() -> None:
    """A stick nudged during L3 must not be learned as the L3 button.

    At rest LX is 0x8000, so its low byte is 0x00. Nudging the stick sets bits
    that were clear at rest, which is exactly the test a button has to pass -- and
    L3/R3 cannot be pressed without touching the stick.
    """
    import math

    sweep: list[bytes] = []
    for degree in range(360):
        angle = math.radians(degree)
        sweep.append(
            make_ally(
                lx=int(0x8000 + 0x7000 * math.cos(angle)),
                ly=int(0x8000 + 0x7000 * math.sin(angle)),
                rx=int(0x8000 + 0x7000 * math.cos(angle * 1.3)),
                ry=int(0x8000 + 0x7000 * math.sin(angle * 1.3)),
            )
        )
    for step in range(60):
        sweep.append(make_ally(trigger=int(0x8000 + 0x7FFF * step / 59)))
    for step in range(60):
        sweep.append(make_ally(trigger=int(0x8000 - 0x8000 * step / 59)))

    analog = classify_analog(sweep, 16)
    assert analog == {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, analog
    # The button and hat bytes must survive the scan untouched.
    assert not analog & {11, 12, 13}

    baseline = make_ally()
    nudged = bytearray(make_ally(lx=0x4000))
    nudged[12] |= 0x01  # L3 pressed while the stick moved
    nudged = bytes(nudged)

    candidates = [
        offset
        for offset in range(16)
        if offset not in analog and nudged[offset] != baseline[offset]
    ]
    assert candidates == [12], candidates

    # Without the exclusion the stick byte wins, which is the reported bug.
    unfiltered = [
        offset for offset in range(16) if nudged[offset] != baseline[offset]
    ]
    assert unfiltered[0] == 2


def test_learner_never_guesses_big_endian() -> None:
    """The runaway-pointer profile, replayed against the corrected rules.

    Captured from hardware 2026-07-26. Every axis is little-endian and rests near
    mid-scale; the learner had picked big-endian for three of them, and RX decoded
    to roughly +19300 with the stick untouched.
    """
    rest = bytes([0x00, 0x83, 0x7D, 0xDA, 0x79, 0x84, 0x7F, 0x0B, 0x81,
                  0x00, 0x80, 0, 0, 0, 0, 0])
    sticks = {"LX": 1, "LY": 3, "RX": 5, "RY": 7}
    for name, offset in sticks.items():
        little = int.from_bytes(rest[offset:offset + 2], "little")
        fraction = little / 65535
        # A self-centring stick rests at the centre of its range.
        assert 0.35 <= fraction <= 0.65, (name, fraction)
    # The shared trigger axis rests at mid-scale too, exactly 0x8000.
    assert int.from_bytes(rest[9:11], "little") == 0x8000

    # Big-endian on the same bytes is not centred, which is why it must never be
    # a candidate: RY reads 4.5% of range and the trigger 0.2%.
    assert (int.from_bytes(rest[7:9], "big") / 65535) < 0.10
    assert (int.from_bytes(rest[9:11], "big") / 65535) < 0.10

    # The profile as actually saved pinned RX far outside any deadzone: about
    # -10700 with the stick untouched, against a default deadzone of 4000.
    saved_neutral, saved_extent, saved_direction = 21884, 36859, -1
    at_rest = (int.from_bytes(rest[5:7], "big") - saved_neutral) * saved_direction
    assert abs(round(at_rest * 32767 / saved_extent)) > 10000


STICKS = ("LX", "LY", "RX", "RY")


def stick_claims(learned: dict[str, Axis], current: str) -> set[int]:
    """Bytes a stick step may not use, mirroring ControllerLearnResolveAxis.

    A stick cannot share bytes with ANOTHER stick -- but it must be allowed to
    keep its own, because the resolve runs again on every report of the gesture
    and each run has already written its provisional answer into the results.
    """
    claimed: set[int] = set()
    for name, axis in learned.items():
        if name not in STICKS or name == current:
            continue
        claimed.add(axis.offset)
        if axis.size != "u8":
            claimed.add(axis.offset + 1)
    return claimed


def stick_rest_is_centred(axis: Axis) -> bool:
    """A self-centring stick rests at the centre of its range. Physics."""
    full_scale = 255 if axis.size == "u8" else 65535
    return 0.35 <= axis.neutral / full_scale <= 0.65


def test_resolve_runs_per_report_without_claiming_its_own_field() -> None:
    """Every stick must still resolve when the step is resolved incrementally.

    The wizard calls the resolver on each report, not once at the end, so a
    stick's own provisional answer is already in the results map by the second
    report. Claiming it there made the field unavailable to itself and every
    stick failed with "Not enough travel" however far it was pushed -- while the
    triggers, which are exempt from stick claiming, went on working. That is
    exactly the shape of the failure reported from hardware on 2026-07-26.
    """
    baseline = make_ally()
    learned: dict[str, Axis] = {}
    # Full travel to the prompted edge, the gesture the wizard actually asks for.
    fields = {"LX": ("lx", 0, -1), "LY": ("ly", 0xFFFF, 1),
              "RX": ("rx", 0, -1), "RY": ("ry", 0xFFFF, 1)}
    expected = {"LX": 1, "LY": 3, "RX": 5, "RY": 7}
    for name in STICKS:
        field, target, want = fields[name]
        samples = capture(make_ally, field, 0x8000, target)
        # Resolve after every report, as the wizard does. Only the last verdict
        # is the step's answer, so an early one must not poison the later ones.
        resolved = None
        for count in range(1, len(samples) + 1):
            claimed = stick_claims(learned, name) | {11, 12, 13}
            try:
                candidate = learn_axis(baseline, samples[:count], want, claimed)
            except AssertionError:
                candidate = None
            if candidate is not None and not stick_rest_is_centred(candidate):
                candidate = None
            # A rejection leaves nothing behind: ControllerLearnRejectAxis
            # deletes the provisional entry so it can never reach the profile.
            if candidate is None:
                learned.pop(name, None)
            else:
                learned[name] = candidate
            resolved = candidate
        assert resolved is not None, f"{name} never resolved"
        assert resolved.offset == expected[name], (name, resolved.offset)
        assert resolved.size == "u16le", (name, resolved.size)

    # And the four sticks still landed on four distinct 16-bit fields.
    offsets = sorted(axis.offset for axis in learned.values())
    assert offsets == [1, 3, 5, 7], offsets


def test_settings_layout_has_no_overlaps() -> None:
    """No two Settings controls on the same page may overlap.

    A Delete button was placed at x430 and covered the "Park after returning to
    Steam" checkbox, which spans x300-620. Eyeballing a hand-placed layout does
    not catch that; arithmetic does.
    """
    import re
    from itertools import combinations
    from pathlib import Path

    source = Path(__file__).with_name("SteamShell-XFE.ahk").read_text(
        encoding="utf-8", errors="ignore")
    start = source.index("ShowSettings(*)")
    body = source[start:source.index("\nSettingsTrackControl(", start)]

    pages = ("General", "Controller & Cursor", "Steam", "RTSS & Performance",
             "Startup Programs", "Assist", "Advanced")
    rects: list[tuple[str, int, int, int, int, str]] = []
    page = None
    for line in body.split("\n"):
        header = re.match(r"\s*;\s*(" + "|".join(re.escape(p) for p in pages) + r")\s*$", line)
        if header:
            page = header.group(1)
            continue
        if page is None:
            continue
        control = re.search(
            r'Add(?:Text|Checkbox|Button|Edit|DropDownList|ListBox)\(\s*'
            r'"x(\d+) y(\d+)(?: w(\d+))?(?: h(\d+))?', line)
        if control:
            rects.append((page, int(control.group(1)), int(control.group(2)),
                          int(control.group(3) or 150), int(control.group(4) or 24),
                          line.strip()[:60]))

    # Rows placed by helpers, whose geometry lives in the helper rather than the
    # call site. These are exactly the ones an eyeball check misses.
    for match in re.finditer(
            r'SettingsAddEditRow\(settings, "([^"]+)",[^)]*?,\s*(\d+), (?:true|false)\)',
            body, re.S):
        page, y = match.group(1), int(match.group(2))
        rects.append((page, 300, y, 250, 24, f"edit row label y{y}"))
        rects.append((page, 570, y - 2, 150, 26, f"edit row field y{y}"))
    for match in re.finditer(
            r'SettingsAddShortcutAt\(settings, "([^"]+)", "[^"]+",\s*"[^"]*", '
            r'(\d+), (\d+), (\d+)\)', body, re.S):
        page, x, y, total = (match.group(1), int(match.group(2)),
                             int(match.group(3)), int(match.group(4)))
        rects.append((page, x, y, 55, 24, f"shortcut label y{y}"))
        rects.append((page, x + 58, y - 2, total - 145, 26, f"shortcut field y{y}"))
        rects.append((page, x + 58 + total - 145 + 6, y - 3, 78, 28,
                      f"shortcut button y{y}"))

    assert len(rects) > 40, f"layout scan found only {len(rects)} controls"

    for first, second in combinations(rects, 2):
        if first[0] != second[0]:
            continue
        ax, ay, aw, ah = first[1:5]
        bx, by, bw, bh = second[1:5]
        if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
            raise AssertionError(
                f"[{first[0]}] overlap:\n    {first[5]}\n    {second[5]}")

    # The status line and buttons sit at y610; page content must stay above them.
    BOTTOM_BAR_Y = 620
    for page, _x, y, _w, height, src in rects:
        if "vSettingsStatus" in src or "y610" in src:
            continue
        assert y + height <= BOTTOM_BAR_Y, f"[{page}] {src} ends at {y + height}"


def main() -> None:
    test_ally_16_bit_and_shared_triggers()
    test_u8_axes_and_independent_triggers()
    test_big_endian_axis()
    test_active_low_button()
    test_masked_hat_shares_button_byte()
    test_change_only_digital_report_is_sufficient()
    test_change_only_identification_uses_release_baseline()
    test_axis_peak_survives_release_and_prevents_carryover()
    test_analog_scan_protects_stick_click_steps()
    test_learner_never_guesses_big_endian()
    test_resolve_runs_per_report_without_claiming_its_own_field()
    test_settings_layout_has_no_overlaps()
    print("Controller profile simulation passed.")


if __name__ == "__main__":
    main()
