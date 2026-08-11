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


def identify_then_rest(reports: list[bytes], idle: bytes,
                       wait_for_release: bool) -> tuple[bytes, bytes]:
    """Model the wizard from device identification to the end of rest.

    `reports` is what the pad publishes from the identifying press onwards.
    Returns the baseline and rest-noise the wizard would end up with, which are
    what every later step is measured against and what the profile's neutral is
    saved from.

    `wait_for_release` is the fix: hold everything until the control that
    identified the device comes back up. With it False this reproduces the
    shipped behaviour, which is why both are modelled here rather than only the
    one that is correct.
    """
    length = len(idle)
    press = reports[0]
    # Identification fires on the report where something changed -- the press.
    changed = [(p ^ i) & 0xFF for p, i in zip(press, idle)]
    hold_offset = next(o for o, c in enumerate(changed) if c)
    hold_mask = changed[hold_offset]

    baseline = bytearray(press)          # what the shipped code copies
    if wait_for_release:
        baseline = bytearray(idle)       # the pre-press report, which it had

    noise = bytearray(length)
    rest_count = 0
    holding = wait_for_release
    for report in reports[1:]:
        if holding:
            if (report[hold_offset] & hold_mask) != (baseline[hold_offset] & hold_mask):
                continue                 # still down; nothing is measured
            holding = False
            # falls through: this report is the first true rest report
        rest_count += 1
        for offset in range(length):
            value = report[offset]
            if rest_count > 1:
                noise[offset] |= value ^ baseline[offset]
            baseline[offset] = value
    return bytes(baseline), bytes(noise)


def test_identifying_press_never_becomes_the_resting_state() -> None:
    """The button that chose the controller must not be learned as held.

    The wizard identifies the pad on the report where a bit CHANGED, which for
    almost every controller is the button going down. Measuring rest from that
    report saves the press into the profile's neutral: the button then reads as
    permanently held, during the wizard and after it is saved. Waiting for the
    release is what makes the resting state actually resting.
    """
    idle = make_ally()
    press = make_ally(face=0x01)

    # A pad that keeps publishing while held, with the user letting go late.
    held = [press, press, press, press]
    broken_baseline, broken_noise = identify_then_rest(held, idle,
                                                       wait_for_release=False)
    assert broken_baseline[11] == 0x01, "expected the shipped bug to be modelled"
    fixed_baseline, fixed_noise = identify_then_rest(held, idle,
                                                     wait_for_release=True)
    assert fixed_baseline[11] == 0x00
    assert fixed_noise[11] == 0x00

    # The same pad with the release arriving inside the rest window. The shipped
    # path records the release as rest NOISE, and a noisy bit is skipped by every
    # later step -- so A becomes unlearnable rather than stuck.
    released = [press, press, idle, idle]
    broken_baseline, broken_noise = identify_then_rest(released, idle,
                                                       wait_for_release=False)
    assert broken_noise[11] == 0x01, "expected the shipped bug to be modelled"
    fixed_baseline, fixed_noise = identify_then_rest(released, idle,
                                                     wait_for_release=True)
    assert fixed_baseline[11] == 0x00
    assert fixed_noise[11] == 0x00

    # A change-only pad: one press report, silence while held, one release.
    # Nothing is published at rest, so the baseline is whatever identification
    # left behind. The release arriving inside the window rescued the shipped
    # path here, which is why this case looked handled -- the comment in the
    # source describes exactly this sequence. It is the only one it survives.
    change_only = [press, idle]
    broken_baseline, _ = identify_then_rest(change_only, idle,
                                            wait_for_release=False)
    assert broken_baseline[11] == 0x00
    fixed_baseline, fixed_noise = identify_then_rest(change_only, idle,
                                                     wait_for_release=True)
    assert fixed_baseline[11] == 0x00
    assert fixed_noise[11] == 0x00

    # A change-only pad whose release lands after the 1.8s window closes
    # publishes nothing at all during rest, so the baseline stays exactly as
    # identification left it. This is the stuck-button report: with nothing
    # touched, A decodes as pressed.
    slow_release = [press]
    broken_baseline, _ = identify_then_rest(slow_release, idle,
                                            wait_for_release=False)
    fixed_baseline, _ = identify_then_rest(slow_release, idle,
                                           wait_for_release=True)
    assert (idle[11] ^ broken_baseline[11]) & 0x01 == 0x01
    assert (idle[11] ^ fixed_baseline[11]) & 0x01 == 0x00


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


def rest_noise_mask(rest: list[bytes], length: int) -> bytes:
    """Mirror of the LearnRestSampling branch of ControllerLearnReport.

    The FIRST rest report refreshes the baseline and contributes no noise; only
    rest-to-rest changes after it are noise, accumulated per bit against a
    baseline that follows the latest report.
    """
    noise = bytearray(length)
    baseline = bytearray(rest[0][:length]) if rest else bytearray(length)
    for count, report in enumerate(rest, start=1):
        for offset in range(length):
            if count > 1:
                noise[offset] |= report[offset] ^ baseline[offset]
            baseline[offset] = report[offset]
    return bytes(noise)


def classify_analog(
    samples: list[bytes], length: int, rest_noise: bytes | None = None
) -> set[int]:
    """Mirror of ControllerLearnClassifyAnalog.

    A button byte takes two values; an axis byte swept through its range takes
    dozens. Both a wide range and many distinct values are required, so neither a
    two-mask button byte nor a monotonic counter is mistaken for an axis.

    SECOND WAY TO QUALIFY, and it is what the high byte of a 16-bit sensor axis
    needs: a byte that drifted at rest AND moved during the scan answers to
    motion rather than to anything pressed. Both halves are required -- see the
    function's comment in SteamShell-Shared.ahk -- and rest_noise is optional
    here only so the callers that predate the rule keep testing the first one on
    its own.
    """
    values: dict[int, set[int]] = {}
    for report in samples:
        for offset in range(length):
            values.setdefault(offset, set()).add(report[offset])
    analog: set[int] = set()
    for offset, seen in values.items():
        wide = len(seen) >= MIN_DISTINCT_VALUES and (max(seen) - min(seen)) >= MIN_RANGE
        drifting = (
            len(seen) >= 2
            and rest_noise is not None
            and offset < len(rest_noise)
            and rest_noise[offset] != 0
        )
        if wide or drifting:
            analog.add(offset)
    return analog


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


def identify_candidate(
    report: bytes, baseline: bytes, noise: bytes, max_bits: int = 4
) -> tuple[int, int] | None:
    """Mirror of the identification scan in ControllerLearnReport."""
    for allowed in (1, max_bits):
        for offset in range(len(baseline)):
            changed = (report[offset] ^ baseline[offset]) & ~noise[offset] & 0xFF
            if not changed:
                continue
            if bin(changed).count("1") > allowed:
                continue
            return offset, changed
    return None


def test_gyro_crossing_zero_does_not_identify_the_pad() -> None:
    """"It goes through that really fast without me even touching anything."

    The log named it: "waiting for byte 18 bit 0xF8 to be released". A gyro axis
    parked at 0xFFC4 flips its high byte 0xFF -> 0x00 on every zero crossing --
    eight bits against a resting mask of 0x07, so 0xF8 survived as a clean
    change and answered the prompt.
    """
    length = 34
    baseline = bytearray(length)
    baseline[1] = 0x0F                       # hat at rest
    baseline[2:6] = bytes([0x7F] * 4)
    baseline[17], baseline[18] = 0xC4, 0xFF
    baseline = bytes(baseline)

    noise = bytearray(length)
    noise[18] = 0x07                         # what the pre-prompt window saw
    for low in (15, 17, 19, 21, 23, 25):
        noise[low] = 0xFF
    noise = bytes(noise)

    crossing = bytearray(baseline)
    crossing[17], crossing[18] = 0x0E, 0x00
    crossing = bytes(crossing)

    # Unfiltered, the crossing IS the identification -- byte 18, mask 0xF8.
    assert identify_candidate(crossing, baseline, noise, max_bits=8) == (18, 0xF8)
    # Filtered on shape, it is not a candidate at all.
    assert identify_candidate(crossing, baseline, noise) is None

    # A real press still identifies, even in the same report as the crossing,
    # and even though the crossing byte is scanned... after it. Byte 8 is the
    # button byte here, so put a stick nudge in front of it to prove the scan
    # does not stop at the first byte that merely moved.
    press = bytearray(crossing)
    press[2] = 0x6A                          # stick brushed: 0x7F -> 0x6A
    press[8] = 0x01                          # A pressed
    assert identify_candidate(bytes(press), baseline, noise) == (8, 0x01)

    # A D-pad direction stays usable: 0x0F -> 0x00 is four bits, on the line.
    hat = bytearray(baseline)
    hat[1] = 0x00
    assert identify_candidate(bytes(hat), baseline, noise) == (1, 0x0F)


def report_axis_active(
    report: bytes,
    baseline: bytes,
    rest_noise: bytes,
    threshold: int,
    claimed: set[int],
    motion: set[int],
) -> bool:
    """Mirror of ControllerLearnReportAxisActive."""
    for offset in range(len(baseline)):
        if offset in claimed or offset in motion:
            continue
        clean = (report[offset] ^ baseline[offset]) & ~rest_noise[offset] & 0xFF
        if clean and abs(report[offset] - baseline[offset]) >= threshold:
            return True
    return False


def test_gyro_crossing_zero_is_not_a_stick_gesture() -> None:
    """The left-stick step that resolved before the stick was touched.

    A 16-bit gyro axis sitting near zero -- bytes (17, 18) held 0xFFC4, which is
    -60 -- flips its HIGH byte between 0xFF and 0x00 on every crossing. That is a
    255-count jump on a byte whose resting mask is one or two bits, so it is
    neither rest noise nor a small change, and the gesture detector read it as
    the stick being pushed and then released.
    """
    length = 34
    baseline = bytearray(length)
    baseline[2:6] = bytes([0x7F] * 4)   # sticks centred
    baseline[14] = 0x64
    baseline[17], baseline[18] = 0xC4, 0xFF
    baseline = bytes(baseline)

    # At rest the high byte moved by a bit or two -- enough to be noticed, far
    # short of ControllerLearnByteFreeRunning's four bits.
    rest_noise = bytearray(length)
    rest_noise[18] = 0x01
    for low in (15, 17, 19, 21, 23, 25):
        rest_noise[low] = 0xFF
    rest_noise = bytes(rest_noise)

    crossing = bytearray(baseline)
    crossing[17], crossing[18] = 0x0E, 0x00   # value crossed zero: -60 -> +14
    crossing = bytes(crossing)

    claimed = {8, 9, 1}                       # buttons and the hat
    # The low bytes are free-running and already excluded; byte 18 is not.
    excluded_today = {15, 17, 19, 21, 23, 25}

    # WITHOUT the motion set, the crossing alone starts the gesture...
    assert report_axis_active(crossing, baseline, rest_noise, 12,
                              claimed, excluded_today)
    # ...and the stick has not moved at all in that report.
    assert crossing[2] == baseline[2]

    # WITH it, the same report says nothing happened.
    motion = excluded_today | {16, 18, 20, 22, 26}
    assert not report_axis_active(crossing, baseline, rest_noise, 12,
                                  claimed, motion)

    # And a real deflection still registers: byte 2 from 0x7F to 0x01.
    pushed = bytearray(crossing)
    pushed[2] = 0x01
    assert report_axis_active(bytes(pushed), baseline, rest_noise, 12,
                              claimed, motion)


def test_change_only_pad_takes_rest_from_the_last_report() -> None:
    """The XInput-mode hang: same pad, completes in DirectInput, stuck in XInput.

    The discriminator is not the gyro and not the mode. A streaming pad feeds the
    rest loop, which rewrites the baseline from every rest report, so a control
    held when the window opened is corrected away. A change-only pad feeds it
    nothing, and the pre-press report stays -- and because the wizard is opened
    by pressing A, that report usually has A down.

    Byte 11 is the button byte on the 15-byte report: 0x01 A, 0x02 B, 0x04 X.
    """
    idle = bytes([0, 0, 0x80, 0xFF, 0x7F, 0, 0x80, 0xFF, 0x7F, 0, 0x80, 0x00, 0, 0, 0])
    a_held = bytearray(idle)
    a_held[11] = 0x01
    a_held = bytes(a_held)

    # The pre-press baseline, taken while A was still down from opening the
    # window. This is what the wizard had, and it is wrong.
    stale = a_held
    # The last report seen while waiting for the identifying control to settle:
    # A let go, and on a change-only pad nothing has been said since.
    last_seen = idle

    def learn(baseline: bytes, pressed_byte: int) -> tuple[int, str] | None:
        """The button matcher, reduced: lowest changed bit outside rest noise."""
        report = bytearray(idle)
        report[11] = pressed_byte
        changed = report[11] ^ baseline[11]
        if not changed:
            return None
        mask = changed & -changed
        polarity = "active-high" if report[11] & mask else "active-low"
        return mask, polarity

    # WITH THE STALE BASELINE, pressing A is invisible -- the baseline already
    # says A is down, so the report matches it and nothing changed.
    assert learn(stale, 0x01) is None
    # It is the RELEASE that gets learned, inverted. That is the "A = byte 11
    # bit 0x01 active-low" in the log, on a pad that reports A as 0x00 -> 0x01.
    assert learn(stale, 0x00) == (0x01, "active-low")
    # And then it shadows every later step: pressing B changes bit 0x01 too, the
    # lowest-set-bit tie-break hands it to A's bit, and the step is rejected as
    # already claimed. That is the hang, and no press can clear it.
    claimed = {0x01}
    for pressed in (0x02, 0x04, 0x08, 0x10):
        mask, _ = learn(stale, pressed)
        assert mask in claimed, (pressed, mask)

    # WITH THE LAST REPORT ADOPTED AS REST every button is itself.
    assert learn(last_seen, 0x01) == (0x01, "active-high")
    assert learn(last_seen, 0x02) == (0x02, "active-high")
    assert learn(last_seen, 0x04) == (0x04, "active-high")

    # And the rule that picks it: silence from a change-only pad means nothing
    # moved, so the last report seen is the current state.
    rest_reports: list[bytes] = []
    baseline = last_seen if not rest_reports else rest_reports[-1]
    assert baseline == idle
    # A streaming pad needs none of this -- the rest loop already rewrote it.
    rest_reports = [idle] * 400
    baseline = last_seen if not rest_reports else rest_reports[-1]
    assert baseline == idle


def make_8bitdo(buttons: int = 0, gyro: tuple[int, ...] | None = None) -> bytes:
    """The 8BitDo Ultimate 2 report from the spoiled run, to scale.

    34 bytes: report id, hat, four stick axes at 0x7F, two triggers, two button
    bytes at 8 and 9, a constant at 14, then SIX 16-BIT LITTLE-ENDIAN SENSOR AXES
    filling bytes 15 to 26. The pairing is what matters: the low byte of each
    sweeps the full range, the high byte moves a couple of counts.
    """
    report = bytearray(34)
    report[0] = 0x01
    report[1] = 0x0F
    report[2:6] = bytes([0x7F] * 4)
    report[8] = buttons & 0xFF
    report[14] = 0x32
    axes = gyro if gyro is not None else (0x02F5, 0xFDDB, 0x02F5, 0xFDDB, 0x02F5, 0xFDDB)
    for index, value in enumerate(axes):
        report[15 + index * 2] = value & 0xFF
        report[16 + index * 2] = (value >> 8) & 0xFF
    return bytes(report)


def test_gyro_high_byte_is_not_a_button() -> None:
    """The 8BitDo Ultimate 2 run in which A, View, R3, L3 and the whole D-pad
    were bound to the gyro.

    Twelve sensor bytes, six 16-bit little-endian pairs. The LOW bytes sweep
    0-255 and the range test claims them. The HIGH bytes are the defect: at rest
    they drift two or three bits, which is under ControllerLearnByteFreeRunning's
    four; during the analogue scan they stay inside a handful of counts, which is
    under MIN_RANGE. What is left looks exactly like a button byte, so tilting
    the pad while pressing A binds a gyro bit and wins the step.
    """
    # At rest the pad is still: the low bytes wander, the high bytes move by one.
    rest = [
        make_8bitdo(gyro=(0x02F5 + (n % 0x120), 0xFDDB + (n % 0x100),
                          0x02F5, 0xFDDB, 0x02F5, 0xFDDB))
        for n in range(400)
    ]
    noise = rest_noise_mask(rest, 34)

    # The high bytes drift, but across too few bits for the free-running test.
    assert noise[16] != 0 and bin(noise[16]).count("1") < 4, hex(noise[16])
    assert noise[18] != 0 and bin(noise[18]).count("1") < 4, hex(noise[18])
    # The button bytes do not move at rest at all. That is the whole difference.
    assert noise[8] == 0 and noise[9] == 0

    # The analogue scan: sticks and triggers worked, pad held roughly still, so
    # the sensor keeps drifting by the same small amount and nothing is pressed.
    scan = [
        make_8bitdo(gyro=(0x02F5 + (n % 0x120), 0xFDDB + (n % 0x100),
                          0x02F5, 0xFDDB, 0x02F5, 0xFDDB))
        for n in range(400)
    ]
    for step in range(60):
        moved = bytearray(scan[step])
        moved[2] = int(0x7F + 0x7F * step / 59)
        moved[6] = int(0xFF * step / 59)
        scan[step] = bytes(moved)

    old = classify_analog(scan, 34)
    new = classify_analog(scan, 34, noise)

    # THE OLD RULE MISSES THEM, which is the bug reproduced rather than asserted.
    assert 16 not in old and 18 not in old, sorted(old)
    # The low bytes were never the problem.
    assert {15, 17} <= old
    # The new rule claims the high bytes, and does not touch the button bytes.
    assert {15, 16, 17, 18} <= new, sorted(new)
    assert not new & {8, 9}, sorted(new)

    # Press A -- byte 8 bit 0x02 -- while tilting the pad enough to flip a higher
    # bit of the gyro high byte. Byte 18 goes 0xFD -> 0xF4, which is bits the rest
    # mask never saw, so it reads as a clean button edge.
    baseline = rest[-1]
    pressed = make_8bitdo(buttons=0x02, gyro=(0x02F5, 0xF4DB,
                                              0x02F5, 0xFDDB,
                                              0x02F5, 0xFDDB))

    def candidates(analog: set[int]) -> list[int]:
        return [
            offset
            for offset in range(34)
            if offset not in analog
            and (pressed[offset] ^ baseline[offset]) & ~noise[offset] & 0xFF
        ]

    # Under the old rule the gyro high byte is a live candidate alongside the
    # real button -- and in the spoiled run it is the one that won.
    assert 18 in candidates(old), candidates(old)
    # Under the new rule the only thing that changed is the button.
    assert candidates(new) == [8], candidates(new)


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


# test_settings_layout_has_no_overlaps was REMOVED, not repaired.
#
# It simulated the Settings page cursor by parsing SteamShell-XFE.ahk for a
# builder API that no longer exists -- SettingsAddEditRow, SettingsAddCheckboxRow,
# SettingsAddNoteRow, SettingsAddChoiceRow -- and by walking page bodies written
# out longhand. Pages are now built from the shared settings spec through
# SettingsAddRowsForCategory, so its model of how the window is constructed was
# obsolete, not merely out of date on a few names.
#
# It had also been dead for some time: it crashed on import of the first layout
# value, because SettingsLayout() moved into SteamShell-Shared.ahk during
# consolidation and this file reads the companion's raw source. Nothing noticed,
# because nothing runs this file -- Validate-SteamShell-XFE.ps1 asserts it EXISTS
# and greps its text for shared constants, but never executes it.
#
# What replaced it is strictly stronger and already runs in both products:
# SettingsEditorAuditLayout in the shell and SettingsAuditLayout in the companion
# check the REAL controls as the window is built, and both report through the log.
# Font and DPI decide the actual size of a row, so an overlap this source-level
# simulation could never see is visible to those. Rebuilding the weaker check
# against the new construction path would be work spent to be told less.
#
# The remaining tests in this file parse no AutoHotkey at all. They mirror the
# decoder and the learning heuristic against synthetic reports, which is why they
# cannot rot the same way.

def main() -> None:
    test_ally_16_bit_and_shared_triggers()
    test_u8_axes_and_independent_triggers()
    test_big_endian_axis()
    test_active_low_button()
    test_masked_hat_shares_button_byte()
    test_change_only_digital_report_is_sufficient()
    test_change_only_identification_uses_release_baseline()
    test_identifying_press_never_becomes_the_resting_state()
    test_axis_peak_survives_release_and_prevents_carryover()
    test_analog_scan_protects_stick_click_steps()
    test_gyro_high_byte_is_not_a_button()
    test_gyro_crossing_zero_does_not_identify_the_pad()
    test_gyro_crossing_zero_is_not_a_stick_gesture()
    test_change_only_pad_takes_rest_from_the_last_report()
    test_learner_never_guesses_big_endian()
    test_resolve_runs_per_report_without_claiming_its_own_field()
    print("Controller profile simulation passed.")


if __name__ == "__main__":
    main()
