import AppKit
import Foundation

struct LoadedImage {
    let name: String
    let rep: NSBitmapImageRep

    var width: Int { rep.pixelsWide }
    var height: Int { rep.pixelsHigh }
}

struct Region {
    let xRange: Range<Int>
    let yRange: Range<Int>
}

enum VerificationError: Error, CustomStringConvertible {
    case usage
    case unreadableImage(String)
    case mismatchedImageSizes(String, String)
    case missingHud(String, Int)
    case duplicateState(String, String, Int)

    var description: String {
        switch self {
        case .usage:
            return "Usage: verify_visual_acceptance.swift before recording processing result error retryable-error"
        case .unreadableImage(let path):
            return "Could not read screenshot: \(path)"
        case .mismatchedImageSizes(let left, let right):
            return "Screenshot sizes differ: \(left) vs \(right)"
        case .missingHud(let state, let changedPixels):
            return "\(state) did not change enough pixels in the expected HUD band (\(changedPixels) changed)"
        case .duplicateState(let left, let right, let changedPixels):
            return "\(left) and \(right) look too similar in the HUD band (\(changedPixels) changed)"
        }
    }
}

let expectedStateNames = [
    "recording",
    "processing",
    "result",
    "error",
    "retryable-error",
]

func loadImage(path: String, name: String) throws -> LoadedImage {
    guard
        let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let rep = NSBitmapImageRep(data: data)
    else {
        throw VerificationError.unreadableImage(path)
    }
    return LoadedImage(name: name, rep: rep)
}

func hudSearchRegion(for image: LoadedImage) -> Region {
    let horizontalInset = max(0, image.width / 12)
    let top = max(0, image.height - 260)
    let bottom = max(top, image.height - 24)

    return Region(
        xRange: horizontalInset..<max(horizontalInset + 1, image.width - horizontalInset),
        yRange: top..<bottom
    )
}

func colorDistance(_ left: NSColor, _ right: NSColor) -> Double {
    guard
        let l = left.usingColorSpace(.deviceRGB),
        let r = right.usingColorSpace(.deviceRGB)
    else {
        return 0
    }

    let dr = Double(l.redComponent - r.redComponent) * 255
    let dg = Double(l.greenComponent - r.greenComponent) * 255
    let db = Double(l.blueComponent - r.blueComponent) * 255
    let da = Double(l.alphaComponent - r.alphaComponent) * 255
    return abs(dr) + abs(dg) + abs(db) + abs(da)
}

func changedPixelCount(
    from left: LoadedImage,
    to right: LoadedImage,
    in region: Region,
    threshold: Double
) throws -> Int {
    guard left.width == right.width, left.height == right.height else {
        throw VerificationError.mismatchedImageSizes(left.name, right.name)
    }

    var count = 0
    for y in region.yRange {
        for x in region.xRange {
            guard
                let leftColor = left.rep.colorAt(x: x, y: y),
                let rightColor = right.rep.colorAt(x: x, y: y)
            else {
                continue
            }

            if colorDistance(leftColor, rightColor) >= threshold {
                count += 1
            }
        }
    }
    return count
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 6 else {
        throw VerificationError.usage
    }

    let before = try loadImage(path: args[0], name: "before")
    let states = try zip(expectedStateNames, args.dropFirst()).map { name, path in
        try loadImage(path: path, name: name)
    }
    let region = hudSearchRegion(for: before)
    let minimumPresenceDelta = 900
    let minimumStateDelta = 120

    for state in states {
        let changed = try changedPixelCount(
            from: before,
            to: state,
            in: region,
            threshold: 72
        )
        guard changed >= minimumPresenceDelta else {
            throw VerificationError.missingHud(state.name, changed)
        }
        print("\(state.name): \(changed) HUD-band pixels changed from baseline")
    }

    for pair in zip(states, states.dropFirst()) {
        let changed = try changedPixelCount(
            from: pair.0,
            to: pair.1,
            in: region,
            threshold: 42
        )
        guard changed >= minimumStateDelta else {
            throw VerificationError.duplicateState(pair.0.name, pair.1.name, changed)
        }
        print("\(pair.0.name) -> \(pair.1.name): \(changed) HUD-band pixels changed")
    }

    print("ChatType visual acceptance passed.")
} catch {
    fputs("Visual acceptance failed: \(error)\n", stderr)
    exit(1)
}
