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

    A Delete button was once placed at x430 and covered the "Park after
    returning to Steam" checkbox, which spans x300-620. Eyeballing a hand-placed
    layout does not catch that; arithmetic does.

    The pages no longer carry literal coordinates: every row places itself from
    a cursor the builders advance. So this scan simulates that cursor instead of
    reading coordinates off the page, which makes it cover EVERY row rather than
    only the ones that happened to be written out longhand.

    The numbers are read out of the source, not repeated here. The columns come
    from SettingsLayout() and each builder's advance comes from its own `y +=`
    line, so changing a builder changes this simulation with it. What is written
    down below is only the SHAPE of each builder -- which controls it emits and
    in which column -- because that is what the builder is.
    """
    import re
    from itertools import combinations
    from pathlib import Path

    source = Path(__file__).with_name("SteamShell-XFE.ahk").read_text(
        encoding="utf-8", errors="ignore")

    def layout_value(name: str) -> int:
        block = re.search(
            r"SettingsLayout\(\) \{.*?\n\}", source, re.S).group(0)
        match = re.search(r'"' + name + r'",\s*(\d+)', block)
        assert match, f"SettingsLayout() has no {name}"
        return int(match.group(1))

    def builder_advance(name: str) -> int:
        block = re.search(
            r"(?m)^" + name + r"\(.*?\n\}", source, re.S)
        assert block, f"{name} was not found"
        match = re.search(r"y \+= (\d+)", block.group(0))
        assert match, f"{name} does not advance the cursor"
        return int(match.group(1))

    label_x = layout_value("labelX")
    label_w = layout_value("labelWidth")
    control_x = layout_value("controlX")
    content_x = layout_value("contentX")
    content_w = layout_value("contentWidth")
    first_row_y = layout_value("contentTop")
    content_bottom = layout_value("contentBottom")

    row_advance = builder_advance("SettingsAddEditRow")
    section_advance = builder_advance("SettingsAddSectionRow")
    section_lead = int(re.search(
        r"(?m)^SettingsAddSectionRow\(.*?top := y \+ (\d+)",
        source, re.S).group(1))
    button_line = int(re.search(
        r"(?m)^SettingsAddButtonRow\(.*?LINE_HEIGHT := (\d+)",
        source, re.S).group(1))
    button_columns = tuple(int(value) for value in re.findall(
        r"\d+",
        re.search(r"(?m)^SettingsAddButtonRow\(.*?COLUMNS := \[([^\]]+)\]",
                  source, re.S).group(1)))
    button_width = int(re.search(
        r"(?m)^SettingsAddButtonRow\(.*?BUTTON_WIDTH := (\d+)",
        source, re.S).group(1))

    # Only the shape lives here. Each entry is (rect list, advance) where a rect
    # is (x, dy, w, h) relative to the cursor.
    def edit_like(width: int) -> list:
        return [(label_x, 3, label_w, 22), (control_x, 0, width, 26)]

    rects: list = []
    page = None
    cursor = first_row_y
    pages = ("General", "Controller & Cursor", "Steam", "RTSS & Performance",
             "Startup Programs", "Assist", "Advanced")
    body = source[source.index("ShowSettings(*)"):source.index(
        "\nSettingsForegroundRetry(")]

    def add(shape: list, note: str) -> None:
        for x, dy, w, h in shape:
            rects.append((page, x, cursor + dy, w, h, note))

    # The page bodies are one flat sequence of builder calls; re-joining wrapped
    # calls onto one line is what makes them parseable in source order.
    flattened = re.sub(r",\s*\n\s*", ", ", body)
    flattened = re.sub(r"\n\s*\. ", " . ", flattened)

    for line in flattened.split("\n"):
        stripped = line.strip()
        assign = re.match(r'category := "([^"]+)"', stripped)
        if assign and assign.group(1) in pages:
            page = assign.group(1)
            continue
        if page is None:
            continue
        if stripped.startswith("y := SettingsFirstRowY()"):
            cursor = first_row_y
            continue

        match = re.match(r"SettingsAddCheckboxRow\(.*?&y(?:, (\d+))?\)", stripped)
        if match:
            height = int(match.group(1) or 26)
            add([(content_x, 0, content_w, height)], stripped[:70])
            cursor += height + 6
            continue
        match = re.match(r"SettingsAddNoteRow\(.*?&y(?:, (\d+))?\)", stripped)
        if match:
            height = int(match.group(1) or 22)
            add([(content_x, 0, content_w, height)], stripped[:70])
            cursor += height + 8
            continue
        if stripped.startswith("SettingsAddSectionRow("):
            add([(content_x, section_lead, content_w, 22)], stripped[:70])
            cursor += section_advance
            continue
        match = re.match(
            r"SettingsAddEditRow\(.*?&y(?:, (?:true|false))?(?:, (\d+))?\)",
            stripped)
        if match:
            add(edit_like(int(match.group(1) or 150)), stripped[:70])
            cursor += row_advance
            continue
        match = re.match(r"SettingsAddChoiceRow\(.*?&y(?:, (\d+))?\)", stripped)
        if match:
            add(edit_like(int(match.group(1) or 200)), stripped[:70])
            cursor += row_advance
            continue
        if stripped.startswith("SettingsAddShortcutRow("):
            add(edit_like(200) + [(778, -1, 92, 28)], stripped[:70])
            cursor += row_advance
            continue
        if stripped.startswith("SettingsAddPathRow("):
            add([(label_x, 3, 160, 22), (466, 0, 300, 26), (774, -1, 96, 28)],
                stripped[:70])
            cursor += row_advance
            continue
        match = re.match(r"SettingsAddButtonRow\(.*?\[(.*)\], &y\)", stripped)
        if match:
            count = len(re.findall(r"\[\s*\"", match.group(1)))
            for index in range(count):
                column = index % len(button_columns)
                if column == 0 and index > 0:
                    cursor += button_line
                rects.append((page, button_columns[column], cursor,
                              button_width, 34, f"button {index + 1}"))
            if count:
                cursor += button_line
            continue
        # The two rows built inline, which still use the cursor variable.
        match = re.match(
            r'\w+ := settings\.Add\w+\(\s*"x(\d+) y" y " w(\d+) h(\d+)',
            stripped)
        if match:
            rects.append((page, int(match.group(1)), cursor, int(match.group(2)),
                          int(match.group(3)), stripped[:70]))
            continue
        match = re.match(r"y \+= (\d+)$", stripped)
        if match:
            cursor += int(match.group(1))
            continue

    assert len(rects) > 90, f"layout scan found only {len(rects)} controls"
    assert len({r[0] for r in rects}) == len(pages), "a page produced no rows"

    for first, second in combinations(rects, 2):
        if first[0] != second[0]:
            continue
        ax, ay, aw, ah = first[1:5]
        bx, by, bw, bh = second[1:5]
        if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
            raise AssertionError(
                f"[{first[0]}] overlap:\n    {first[5]}\n    {second[5]}")

    # Rows may now run past the bottom of the window, because the viewport
    # scrolls -- that is the whole point of the port. What must NOT happen is a
    # row starting above the viewport, which would draw over the page title.
    for page_name, _x, y, _w, _h, note in rects:
        assert y >= first_row_y, f"[{page_name}] {note} starts at {y}"

    # A page that needs no scrolling should not have gained any: if the four
    # shortest pages have grown past the viewport, a row was added in the wrong
    # place rather than the page genuinely needing the space.
    tallest = {}
    for page_name, _x, y, _w, h, _note in rects:
        tallest[page_name] = max(tallest.get(page_name, 0), y + h)
    assert tallest["General"] <= content_bottom, (
        f"General now needs scrolling ({tallest['General']})")


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
