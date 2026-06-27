import Testing
import Foundation
@testable import WebSceneKit

@Suite("WebSceneValue")
struct WebSceneValueTests {
    @Test func fromString() {
        let v = WebSceneValue.from("hello")
        #expect(v.string == "hello")
    }

    @Test func fromBool() {
        let v = WebSceneValue.from(true)
        #expect(v.bool == true)
    }

    @Test func fromNumber() {
        let v = WebSceneValue.from(42)
        #expect(v.number == 42)
        #expect(v.int == 42)
    }

    @Test func fromArray() {
        let v = WebSceneValue.from([1, 2, 3])
        #expect(v.array?.count == 3)
    }

    @Test func fromObject() {
        let v = WebSceneValue.from(["a": 1, "b": "x"])
        #expect(v.object?["a"]?.number == 1)
        #expect(v.object?["b"]?.string == "x")
    }

    @Test func fromNull() {
        let v = WebSceneValue.from(NSNull())
        if case .null = v { } else { Issue.record("expected .null") }
    }
}

@Suite("WebSceneConfig")
struct WebSceneConfigTests {
    @Test func indexURLAppends() {
        let base = URL(fileURLWithPath: "/tmp/web")
        let config = WebSceneConfig(bundleURL: base, indexFileName: "foo.html")
        #expect(config.indexURL.lastPathComponent == "foo.html")
    }

    @Test func allowedReadRootDefaultsToBundle() {
        let base = URL(fileURLWithPath: "/tmp/web")
        let config = WebSceneConfig(bundleURL: base)
        #expect(config.allowedReadRoot == base)
    }
}
