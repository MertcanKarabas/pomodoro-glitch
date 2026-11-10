import Foundation
import Testing
@testable import SpiderCore

@Suite("AppVersion")
struct AppVersionTests {
    @Test func parsesTagsAndPlainVersions() {
        #expect(AppVersion("v1.2.3")?.parts == [1, 2, 3])
        #expect(AppVersion("1.0")?.parts == [1, 0])
        #expect(AppVersion(" 2.1-beta ")?.parts == [2, 1])
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test func comparesNumerically() {
        let v = { (text: String) in AppVersion(text)! }
        #expect(v("1.0") == v("1.0.0"))
        #expect(v("v1.0") == v("1.0"))
        #expect(v("1.0.1") > v("1.0"))
        #expect(v("1.10") > v("1.9"))
        #expect(v("2.0") > v("1.99.99"))
        #expect(!(v("1.0") > v("1.0")))
        #expect(v("1.1").description == "1.1")
    }
}

@Suite("UpdateCheck")
struct UpdateCheckTests {
    private func releaseJSON(tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String] = ["SpiderPomodoro.dmg"]) -> Data {
        let assetList = assets.map {
            #"{"name": "\#($0)", "browser_download_url": "https://github.com/o/r/releases/download/\#(tag)/\#($0)"}"#
        }.joined(separator: ",")
        return Data("""
        {"tag_name": "\(tag)", "html_url": "https://github.com/o/r/releases/tag/\(tag)",
         "draft": \(draft), "prerelease": \(prerelease), "body": "notes", "assets": [\(assetList)]}
        """.utf8)
    }

    @Test func newerReleaseIsAnUpdateWithItsDMG() throws {
        let update = try UpdateCheck.update(fromLatestReleaseJSON: releaseJSON(tag: "v1.1"), current: AppVersion("1.0")!)
        #expect(update?.version == AppVersion("1.1"))
        #expect(update?.pageURL.absoluteString == "https://github.com/o/r/releases/tag/v1.1")
        #expect(update?.downloadURL?.lastPathComponent == "SpiderPomodoro.dmg")
    }

    @Test func sameOrOlderIsNotAnUpdate() throws {
        #expect(try UpdateCheck.update(fromLatestReleaseJSON: releaseJSON(tag: "v1.0"), current: AppVersion("1.0")!) == nil)
        #expect(try UpdateCheck.update(fromLatestReleaseJSON: releaseJSON(tag: "v0.9"), current: AppVersion("1.0")!) == nil)
    }

    @Test func draftsAndBetasAreIgnored() throws {
        let current = AppVersion("1.0")!
        #expect(try UpdateCheck.update(fromLatestReleaseJSON: releaseJSON(tag: "v2.0", draft: true), current: current) == nil)
        #expect(try UpdateCheck.update(fromLatestReleaseJSON: releaseJSON(tag: "v2.0", prerelease: true), current: current) == nil)
    }

    @Test func releaseWithoutDMGStillPointsToItsPage() throws {
        let update = try UpdateCheck.update(fromLatestReleaseJSON: releaseJSON(tag: "v1.1", assets: []), current: AppVersion("1.0")!)
        #expect(update?.downloadURL == nil)
        #expect(update?.pageURL.lastPathComponent == "v1.1")
    }

    @Test func garbageIsAnError() {
        #expect(throws: (any Error).self) {
            try UpdateCheck.update(fromLatestReleaseJSON: Data("nope".utf8), current: AppVersion("1.0")!)
        }
    }
}
