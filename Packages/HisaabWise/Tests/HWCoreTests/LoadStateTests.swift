import HWCore
import Testing

/// ADR-0016 — one state taxonomy for every screen, and `offline` is never rendered as `failed`.
@Suite("LoadState")
struct LoadStateTests {
    @Test("distinguishes offline from failed")
    func offlineIsNotFailed() {
        let offline = LoadState<Int>.offline
        let failed = LoadState<Int>.failed(.unknown)

        #expect(offline != failed)
        #expect(offline.isOffline)
        #expect(!offline.isFailed)
        #expect(failed.isFailed)
        #expect(!failed.isOffline)
    }

    @Test("exposes the loaded value and nothing else")
    func exposesTheLoadedValue() {
        #expect(LoadState.loaded(42).value == 42)
        #expect(LoadState<Int>.loading.value == nil)
        #expect(LoadState<Int>.empty.value == nil)
        #expect(LoadState<Int>.offline.value == nil)
        #expect(LoadState<Int>.failed(.unknown).value == nil)
    }

    @Test("carries an error code, never server prose")
    func failedCarriesACodeOnly() {
        let state = LoadState<Int>.failed(ErrorCode(rawValue: "RATE_LIMITED"))

        #expect(state == .failed(ErrorCode(rawValue: "RATE_LIMITED")))
        #expect(state != .failed(.unknown))
    }
}
