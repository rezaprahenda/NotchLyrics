import Foundation

// Test runner kecil tanpa XCTest, supaya bisa jalan hanya dengan Command Line Tools.
// Jalankan: ./test.sh

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String,
            file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("  ✗ \(message)  (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String,
                               file: StaticString = #file, line: UInt = #line) {
    expect(a == b, "\(message): \(a) ≠ \(b)", file: file, line: line)
}

func near(_ a: Double, _ b: Double, _ tol: Double = 0.001) -> Bool { abs(a - b) <= tol }

func suite(_ name: String, _ body: () -> Void) {
    let before = failures
    body()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

@main
struct TestMain {
    static func main() {
        lrcTests()
        priorityTests()
        peekQueueTests()
        pomodoroTests()
        prayerTests()
        print("\n\(checks) pemeriksaan, \(failures) gagal")
        exit(failures == 0 ? 0 : 1)
    }
}
