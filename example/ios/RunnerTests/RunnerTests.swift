import Flutter
import UIKit
import XCTest

@testable import flutter_startup_tracer

class RunnerTests: XCTestCase {
  func testProcessStartIsInThePast() {
    let micros = FlutterStartupTracerPlugin.processStartEpochMicros()
    XCTAssertNotNil(micros)
    let nowMicros = Int64(Date().timeIntervalSince1970 * 1_000_000)
    XCTAssertLessThanOrEqual(micros!, nowMicros)
  }
}
