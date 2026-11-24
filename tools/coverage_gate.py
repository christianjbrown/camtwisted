#!/usr/bin/env python3
"""Fails unless the libraries and the audio driver are fully covered by the unit tests.

Every source file must have every line, every function and every region
executed. Regions are the finest measure Swift's coverage offers: each
branch of an if, each side of a ??, each closure. The toolchain has no
separate branch count for Swift, so regions stand in for it.

Usage: coverage_gate.py <llvm-cov export json> <sources dir>
"""
import json
import sys

# Files that talk straight to hardware or the operating system: a camera,
# the screen, the virtual camera, the sound devices. A unit test cannot
# give them a camera or a permission, so they are kept free of logic and
# left out of the gate.
DEVICE_BOUNDARY = {
    "CameraSource.swift",
    "DisplaySource.swift",
    "WindowSource.swift",
    "VirtualCameraSink.swift",
    "AudioOutputDevices.swift",
    # The network listener: its failure paths need a network that fails.
    "WebStreamServer.swift",
    # The line to an RTMP server, for the same reason.
    "RTMPConnection.swift",
    # The system's video encoder: its failure paths need hardware that fails.
    "H264Encoder.swift",
    # The system's sound encoder and the microphone, likewise.
    "AACEncoder.swift",
    "MicrophoneSource.swift",
    # The system's audio engine, and the tap that hears what a player plays.
    "EngineSoundMixer.swift",
    "PlayerSoundTap.swift",
    # The engine that plays the mix to the virtual microphone's driver.
    "VirtualMicrophoneSink.swift",
    # The line to a VNC server: what is said over it is tested in the core.
    "VNCSource.swift",
    # The system's person finder, which needs a real person to find.
    "VisionPersonMasker.swift",
    # The system's face finder, which needs a real face to find.
    "VisionFaceTracker.swift",
}
MEASURES = ("lines", "functions", "regions")


def main() -> int:
    report_path, sources = sys.argv[1], sys.argv[2]
    exempt = set(DEVICE_BOUNDARY)

    with open(report_path) as handle:
        files = json.load(handle)["data"][0]["files"]

    totals = {measure: [0, 0] for measure in MEASURES}
    failures = []
    for entry in files:
        name = entry["filename"]
        if sources not in name:
            continue
        short = name.split("/")[-1]
        if short in exempt:
            continue
        summary = entry["summary"]
        gaps = []
        for measure in MEASURES:
            covered, count = summary[measure]["covered"], summary[measure]["count"]
            totals[measure][0] += covered
            totals[measure][1] += count
            if covered < count:
                gaps.append("%s %d of %d" % (measure, covered, count))
        if gaps:
            failures.append("  %s: %s" % (name.split(sources)[-1], ", ".join(gaps)))

    for measure in MEASURES:
        covered, count = totals[measure]
        print("  %s: %d of %d" % (measure, covered, count))
    print("  left out (device boundary): %s" % ", ".join(sorted(DEVICE_BOUNDARY)))
    if failures:
        print("  not fully covered:")
        print("\n".join(sorted(failures)))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
