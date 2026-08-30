import AppKit
import CoreGraphics
import Foundation

/// Scroll-stitch math adapted from Vorssaint's screenshot tool.
struct ScreenshotScrollingRegion: Sendable {
    let displayID: CGDirectDisplayID
    let pixelRect: CGRect
    let anchorRect: CGRect
    let scale: CGFloat
}

enum ScreenshotScrollingSupport {
    static let maximumDuration: TimeInterval = 120
    static let maximumFrames = 512
    static let maximumRetainedPixels = 60_000_000
    static let maximumPixels = 60_000_000

    struct ScrollingSample: Equatable {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        var isValid: Bool {
            width > 0 && height > 0 && pixels.count == width * height
        }
    }

    enum ScrollingDirection: Equatable {
        case forward
        case backward
    }

    enum ScrollingTransition: Equatable {
        case end
        case advanced(overlap: Int, direction: ScrollingDirection, contentColumns: Range<Int>)
        case unmatched
    }

    static func makeRegion(
        selection: CGRect,
        screen: NSScreen,
        anchorRect: CGRect
    ) -> ScreenshotScrollingRegion? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let scale = screen.backingScaleFactor
        let viewSize = screen.frame.size
        let pixelSize = CGSize(width: viewSize.width * scale, height: viewSize.height * scale)
        let displayPixels = CGRect(origin: .zero, size: pixelSize)
        let raw = CropGeometry.cropRect(
            localRect: selection,
            screenSize: viewSize,
            imageSize: pixelSize
        )
        let pixelRect = snappedPixelRect(raw, in: displayPixels)
        guard !pixelRect.isEmpty else { return nil }
        return ScreenshotScrollingRegion(
            displayID: CGDirectDisplayID(number.uint32Value),
            pixelRect: pixelRect,
            anchorRect: anchorRect,
            scale: scale
        )
    }

    static func scrollingSamplesAreStable(
        _ previous: ScrollingSample,
        _ current: ScrollingSample,
        contentColumns: Range<Int>? = nil
    ) -> Bool {
        previous.isValid && current.isValid
            && previous.width == current.width
            && previous.height == current.height
            && scrollingDifference(previous, current, columns: contentColumns ?? 0..<previous.width) <= 1.5
    }

    static func scrollingTransition(
        previous: ScrollingSample,
        current: ScrollingSample,
        contentColumns: Range<Int>? = nil
    ) -> ScrollingTransition {
        guard previous.isValid, current.isValid,
              previous.width == current.width,
              previous.height == current.height,
              previous.height >= 24
        else { return .unmatched }

        let columns = contentColumns ?? 0..<previous.width
        guard columns.lowerBound >= 0,
              columns.upperBound <= previous.width,
              !columns.isEmpty
        else { return .unmatched }

        if scrollingSamplesAreStable(previous, current, contentColumns: columns) {
            return .end
        }

        let height = previous.height
        let minimumAdvance = max(2, Int((Double(height) * 0.01).rounded()))
        let maximumAdvance = min(height - 8, Int((Double(height) * 0.88).rounded()))
        guard minimumAdvance <= maximumAdvance else { return .unmatched }

        struct Match {
            let advance: Int
            let reversed: Bool
            let contentColumns: Range<Int>
            let supportingTiles: Int
            let longestRun: Int
            let matchingRows: Int
            let difference: Double
        }

        let tiles = scrollingColumnTiles(in: columns, sampleWidth: previous.width)
        let movingTiles = tiles.filter {
            scrollingDifference(previous, current, columns: $0) > 1.5
        }
        guard !movingTiles.isEmpty else { return .unmatched }

        var matches: [Match] = []
        for advance in minimumAdvance...maximumAdvance {
            for reversed in [false, true] {
                guard let match = scrollingCandidate(
                    previous: previous,
                    current: current,
                    advance: advance,
                    reversed: reversed,
                    tiles: movingTiles
                ) else { continue }
                matches.append(
                    Match(
                        advance: advance,
                        reversed: reversed,
                        contentColumns: match.contentColumns,
                        supportingTiles: match.supportingTiles,
                        longestRun: match.longestRun,
                        matchingRows: match.matchingRows,
                        difference: match.difference
                    )
                )
            }
        }
        guard !matches.isEmpty else { return .unmatched }
        matches.sort {
            if $0.contentColumns.count != $1.contentColumns.count {
                return $0.contentColumns.count > $1.contentColumns.count
            }
            if $0.supportingTiles != $1.supportingTiles {
                return $0.supportingTiles > $1.supportingTiles
            }
            if $0.longestRun != $1.longestRun { return $0.longestRun > $1.longestRun }
            if $0.matchingRows != $1.matchingRows { return $0.matchingRows > $1.matchingRows }
            return $0.difference < $1.difference
        }

        let best = matches[0]
        let requiredRun = max(8, min(28, height / 12))
        guard best.longestRun >= requiredRun else { return .unmatched }

        if let rival = matches.dropFirst().first(where: {
            $0.reversed != best.reversed || abs($0.advance - best.advance) > 2
        }),
           rival.contentColumns.count >= best.contentColumns.count - 1,
           rival.supportingTiles >= best.supportingTiles - 1,
           rival.longestRun >= best.longestRun - 2,
           rival.matchingRows >= best.matchingRows - max(3, best.supportingTiles * 3),
           rival.difference <= best.difference + 0.75 {
            return .unmatched
        }
        return .advanced(
            overlap: height - best.advance,
            direction: best.reversed ? .backward : .forward,
            contentColumns: best.contentColumns
        )
    }

    static func scrollingFixedBottomRows(
        previous: ScrollingSample,
        current: ScrollingSample,
        overlap: Int,
        contentColumns: Range<Int>
    ) -> Int {
        guard previous.isValid, current.isValid,
              previous.width == current.width,
              previous.height == current.height,
              overlap > 0, overlap < previous.height,
              contentColumns.lowerBound >= 0,
              contentColumns.upperBound <= previous.width,
              !contentColumns.isEmpty
        else { return 0 }

        var rows = 0
        for row in stride(from: previous.height - 1, through: 0, by: -1) {
            let start = row * previous.width
            var difference = 0
            for column in contentColumns {
                difference += abs(Int(previous.pixels[start + column]) - Int(current.pixels[start + column]))
            }
            guard Double(difference) / Double(contentColumns.count) <= 2 else { break }
            rows += 1
        }

        let minimumRows = max(4, min(12, previous.height / 100))
        guard rows >= minimumRows, rows < overlap else { return 0 }
        return rows
    }

    static func scrollingNewContentRows(
        imageHeight: Int,
        overlap: Int,
        fixedBottomRows: Int
    ) -> Range<Int>? {
        guard imageHeight > 0,
              overlap > 0, overlap < imageHeight,
              fixedBottomRows >= 0, fixedBottomRows < overlap
        else { return nil }
        return (overlap - fixedBottomRows)..<(imageHeight - fixedBottomRows)
    }

    static func scrollingPixelRange(
        sampleColumns: Range<Int>,
        sampleWidth: Int,
        imageWidth: Int
    ) -> Range<Int>? {
        guard sampleWidth > 0, imageWidth > 0,
              sampleColumns.lowerBound >= 0,
              sampleColumns.upperBound <= sampleWidth,
              !sampleColumns.isEmpty else { return nil }
        let lower = sampleColumns.lowerBound * imageWidth / sampleWidth
        let upper = (sampleColumns.upperBound * imageWidth + sampleWidth - 1) / sampleWidth
        guard lower >= 0, upper <= imageWidth, lower < upper else { return nil }
        return lower..<upper
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        rect.intersection(bounds).isNull ? .zero : rect.intersection(bounds)
    }

    private static func snappedPixelRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite
        else { return CGRect(origin: bounds.origin, size: evenSize(bounds.size)) }

        let clamped = rect.intersection(bounds).isNull ? bounds : rect.intersection(bounds)
        var origin = CGPoint(x: clamped.origin.x.rounded(.down), y: clamped.origin.y.rounded(.down))
        var size = evenSize(clamped.size)
        if origin.x + size.width > bounds.maxX {
            origin.x = max(bounds.minX, (bounds.maxX - size.width).rounded(.down))
        }
        if origin.y + size.height > bounds.maxY {
            origin.y = max(bounds.minY, (bounds.maxY - size.height).rounded(.down))
        }
        size = evenSize(
            CGSize(
                width: min(size.width, bounds.maxX - origin.x),
                height: min(size.height, bounds.maxY - origin.y)
            )
        )
        return CGRect(origin: origin, size: size)
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, Int(size.width.rounded(.down) / 2) * 2),
            height: max(2, Int(size.height.rounded(.down) / 2) * 2)
        )
    }

    private static func scrollingDifference(
        _ lhs: ScrollingSample,
        _ rhs: ScrollingSample,
        columns: Range<Int>
    ) -> Double {
        guard columns.lowerBound >= 0,
              columns.upperBound <= lhs.width,
              !columns.isEmpty else { return .infinity }
        let topInset = max(0, lhs.height / 24)
        var difference = 0
        var count = 0
        for row in topInset..<(lhs.height - topInset) {
            let start = row * lhs.width
            for column in columns {
                difference += abs(Int(lhs.pixels[start + column]) - Int(rhs.pixels[start + column]))
                count += 1
            }
        }
        return count > 0 ? Double(difference) / Double(count) : .infinity
    }

    private struct ScrollingCandidate {
        let contentColumns: Range<Int>
        let supportingTiles: Int
        let longestRun: Int
        let matchingRows: Int
        let difference: Double
    }

    private static func scrollingColumnTiles(in columns: Range<Int>, sampleWidth: Int) -> [Range<Int>] {
        let tileWidth = max(2, sampleWidth / 8)
        var tiles: [Range<Int>] = []
        var lower = columns.lowerBound
        while lower < columns.upperBound {
            let upper = min(columns.upperBound, lower + tileWidth)
            if upper - lower >= 2 || tiles.isEmpty {
                tiles.append(lower..<upper)
            }
            lower = upper
        }
        return tiles
    }

    private static func scrollingCandidate(
        previous: ScrollingSample,
        current: ScrollingSample,
        advance: Int,
        reversed: Bool,
        tiles: [Range<Int>]
    ) -> ScrollingCandidate? {
        let requiredRun = max(8, min(28, previous.height / 12))
        let matches = tiles.map { tile -> (Range<Int>, ScrollingRowMatch?) in
            guard let match = scrollingMatch(
                previous: previous,
                current: current,
                advance: advance,
                reversed: reversed,
                columns: tile
            ),
            match.longestRun >= requiredRun,
            match.matchingRows >= max(requiredRun, match.comparedRows / 3)
            else { return (tile, nil) }
            return (tile, match)
        }

        let minimumTiles = matches.count >= 3 ? 2 : 1
        var runs: [[(Range<Int>, ScrollingRowMatch)]] = []
        var run: [(Range<Int>, ScrollingRowMatch)] = []
        var skippedOneTile = false
        for (tile, match) in matches {
            if let match {
                run.append((tile, match))
            } else if !run.isEmpty, !skippedOneTile {
                skippedOneTile = true
            } else {
                if !run.isEmpty { runs.append(run) }
                run = []
                skippedOneTile = false
            }
        }
        if !run.isEmpty { runs.append(run) }

        return runs.compactMap { supported -> ScrollingCandidate? in
            guard supported.count >= minimumTiles,
                  let first = supported.first,
                  let last = supported.last else { return nil }
            let contentColumns = first.0.lowerBound..<last.0.upperBound
            guard let combined = scrollingMatch(
                previous: previous,
                current: current,
                advance: advance,
                reversed: reversed,
                columns: contentColumns
            ),
            combined.longestRun >= requiredRun,
            combined.matchingRows >= max(requiredRun, combined.comparedRows / 3)
            else { return nil }
            return ScrollingCandidate(
                contentColumns: contentColumns,
                supportingTiles: supported.count,
                longestRun: combined.longestRun,
                matchingRows: combined.matchingRows,
                difference: combined.difference
            )
        }.max {
            if $0.contentColumns.count != $1.contentColumns.count {
                return $0.contentColumns.count < $1.contentColumns.count
            }
            if $0.matchingRows != $1.matchingRows {
                return $0.matchingRows < $1.matchingRows
            }
            return $0.difference > $1.difference
        }
    }

    private struct ScrollingRowMatch {
        let longestRun: Int
        let matchingRows: Int
        let comparedRows: Int
        let difference: Double
    }

    private static func scrollingMatch(
        previous: ScrollingSample,
        current: ScrollingSample,
        advance: Int,
        reversed: Bool,
        columns: Range<Int>
    ) -> ScrollingRowMatch? {
        let width = previous.width
        let edgeInset = max(2, previous.height / 10)
        let lastRow = previous.height - advance - edgeInset
        guard lastRow > edgeInset,
              columns.lowerBound >= 0,
              columns.upperBound <= width,
              !columns.isEmpty else { return nil }

        var longestRun = 0
        var run = 0
        var matchingRows = 0
        var comparedRows = 0
        var totalDifference = 0
        var comparedPixels = 0
        for currentRow in edgeInset..<lastRow {
            let previousRow = currentRow + advance
            let previousStart = (reversed ? currentRow : previousRow) * width
            let currentStart = (reversed ? previousRow : currentRow) * width
            var rowDifference = 0
            for column in columns {
                rowDifference += abs(
                    Int(previous.pixels[previousStart + column]) - Int(current.pixels[currentStart + column])
                )
            }
            let rowPixels = columns.count
            let average = Double(rowDifference) / Double(rowPixels)
            totalDifference += rowDifference
            comparedPixels += rowPixels
            comparedRows += 1
            if average <= 8 {
                run += 1
                matchingRows += 1
                longestRun = max(longestRun, run)
            } else {
                run = 0
            }
        }
        guard comparedPixels > 0 else { return nil }
        return ScrollingRowMatch(
            longestRun: longestRun,
            matchingRows: matchingRows,
            comparedRows: comparedRows,
            difference: Double(totalDifference) / Double(comparedPixels)
        )
    }
}
