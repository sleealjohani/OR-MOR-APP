import XCTest
import simd
@testable import ORMOR

final class CameraPathTests: XCTestCase {
    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 1e-3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(a, b), accuracy, "\(a) vs \(b)", file: file, line: line)
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(1, abs(simd_dot(a.vector, b.vector))))
    }

    func testPathStartsAndEndsOnKeys() {
        let keys = CafeLayout.route(to: .table(1), aspect: 0.46)
        let path = CameraPath(keys: keys, duration: 2)
        assertClose(path.pose(atProgress: 0).position, keys.first!.position)
        assertClose(path.pose(atProgress: 1).position, keys.last!.position)
        XCTAssertLessThan(angle(path.pose(atProgress: 1).orientation, keys.last!.orientation), 1e-3)
    }

    func testPathPassesThroughEveryKey() {
        let keys = CafeLayout.introKeys
        let path = CameraPath(keys: keys, duration: 7)
        for (key, knot) in zip(keys, path.knots) {
            assertClose(path.pose(atSpline: knot).position, key.position)
        }
    }

    func testReversedPathRetracesForwardPath() {
        let path = CameraPath(keys: CafeLayout.route(to: .cashier, aspect: 0.46), duration: 2, easing: .glide)
        let back = path.reversed()
        for i in 0...20 {
            let s = Float(i) / 20
            assertClose(path.pose(atSpline: s).position, back.pose(atSpline: 1 - s).position, accuracy: 1e-3)
            XCTAssertLessThan(angle(path.pose(atSpline: s).orientation, back.pose(atSpline: 1 - s).orientation), 2e-3)
        }
    }

    func testMotionIsContinuous() {
        // No frame should jump more than a small fraction of the route at 60 fps.
        for spot in CafeLayout.interactiveSpots {
            let keys = CafeLayout.route(to: spot, aspect: 0.46)
            let path = CameraPath(keys: keys, duration: 2, easing: .glide)
            var previous = path.pose(atProgress: 0)
            for i in 1...120 {
                let pose = path.pose(atProgress: Double(i) / 120)
                XCTAssertLessThan(simd_distance(pose.position, previous.position), 0.25, "\(spot) frame \(i)")
                XCTAssertLessThan(angle(pose.orientation, previous.orientation), 0.12, "\(spot) frame \(i)")
                XCTAssertEqual(simd_length(pose.orientation.vector), 1, accuracy: 1e-4)
                previous = pose
            }
        }
    }

    func testOverheadViewLooksStraightDown() {
        guard let table = CafeLayout.table(2) else { return XCTFail("missing table") }
        let pose = CafeLayout.tableApproach(table, aspect: 0.46).last!
        assertClose(pose.forward, [0, -1, 0], accuracy: 1e-4)
        // Screen-up points deeper into the café (-Z), matching the reference photo.
        assertClose(pose.orientation.act([0, 1, 0]), [0, 0, -1], accuracy: 1e-4)
        XCTAssertLessThan(pose.position.y, CafeLayout.ceilingHeight)
    }

    func testEasingCurvesAreMonotonicAndBounded() {
        for easing in [CameraEasing.linear, .cinematic, .glide] {
            XCTAssertEqual(easing.apply(0), 0, accuracy: 1e-9)
            XCTAssertEqual(easing.apply(1), 1, accuracy: 1e-9)
            var last = 0.0
            for i in 1...200 {
                let v = easing.apply(Double(i) / 200)
                XCTAssertGreaterThanOrEqual(v, last - 1e-9, "\(easing) at \(i)")
                last = v
            }
        }
    }

    func testHotspotNamesRoundTrip() {
        for spot in CafeLayout.interactiveSpots {
            XCTAssertEqual(CafeSpot(hotspotName: CafeLayout.hotspotPrefix + spot.id), spot)
        }
        XCTAssertNil(CafeSpot(hotspotName: "sign"))
    }
}

@MainActor
final class CameraDirectorTests: XCTestCase {
    func testTableVisitAndBackReturnsToHub() {
        let director = CameraDirector()
        director.jumpToHub()
        director.go(to: .table(3))
        XCTAssertTrue(director.isMoving)
        for _ in 0..<400 { director.advance(by: 1.0 / 60) }
        XCTAssertEqual(director.spot, .table(3))
        XCTAssertTrue(director.canGoBack)

        director.back()
        for _ in 0..<400 { director.advance(by: 1.0 / 60) }
        XCTAssertEqual(director.spot, .hub)
        XCTAssertLessThan(simd_distance(director.currentPose.position, CafeLayout.hubPose.position), 1e-3)
    }

    func testIntroOpensDoorsAndLandsAtHub() {
        let director = CameraDirector()
        var opened = false
        director.onDoorsShouldOpen = { opened = true }
        director.playIntro()
        for _ in 0..<(60 * 9) { director.advance(by: 1.0 / 60) }
        XCTAssertTrue(opened)
        XCTAssertEqual(director.spot, .hub)
    }

    func testSpotToSpotThenHome() {
        let director = CameraDirector()
        director.jumpToHub()
        director.go(to: .cashier)
        for _ in 0..<400 { director.advance(by: 1.0 / 60) }
        director.go(to: .management)
        for _ in 0..<400 { director.advance(by: 1.0 / 60) }
        XCTAssertEqual(director.spot, .management)
        director.goHome()
        for _ in 0..<400 { director.advance(by: 1.0 / 60) }
        XCTAssertEqual(director.spot, .hub)
        XCTAssertFalse(director.canGoBack)
    }
}
