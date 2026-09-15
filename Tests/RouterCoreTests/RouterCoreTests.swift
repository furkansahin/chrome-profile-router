import Foundation
import Testing
@testable import RouterCore

struct RouterCoreTests {
    let profiles = [ChromeProfile(id: "Default", name: "Personal"), ChromeProfile(id: "Profile 1", name: "Alex (Person 1)")]

    @Test func testITermUsesSharedWorkProfile() {
        let request = LinkRequest(rawURL: "https://example.com/iterm", sourceBundleID: "com.googlecode.iterm2")
        #expect(Router.route(request, workProfileID: "Profile 1", profiles: profiles) == .automatic(profileID: "Profile 1"))
        #expect(Router.route(request, workProfileID: "Default", profiles: profiles) == .automatic(profileID: "Default"))
    }

    @Test func testSourceAppsCanBeAddedAndRemoved() {
        let configured: Set<String> = ["com.apple.Notes"]
        for id in [Router.slackBundleID, "com.googlecode.iterm2", "com.apple.Notes.fake"] {
            #expect(Router.route(LinkRequest(rawURL: "https://example.com", sourceBundleID: id), workProfileID: "Profile 1",
                                 profiles: profiles, workSourceBundleIDs: configured) == .picker(message: nil))
        }
        #expect(Router.route(LinkRequest(rawURL: "https://example.com", sourceBundleID: "com.apple.Notes"), workProfileID: "Profile 1",
                             profiles: profiles, workSourceBundleIDs: configured) == .automatic(profileID: "Profile 1"))
        #expect(Router.route(LinkRequest(rawURL: "https://example.com", sourceBundleID: Router.slackBundleID), workProfileID: "Profile 1",
                             profiles: profiles, workSourceBundleIDs: []) == .picker(message: nil))
    }

    @Test func testMigrationAddsDefaultsButDoesNotUndoRemovedApps() throws {
        #expect(WorkSourceApp.restore(nil) == WorkSourceApp.defaults)
        #expect(WorkSourceApp.restore(Data("[]".utf8)).isEmpty)
        #expect(WorkSourceApp.restore(Data("invalid".utf8)).isEmpty)
        let onlyITerm = [WorkSourceApp(id: "com.googlecode.iterm2", name: "iTerm")]
        #expect(WorkSourceApp.restore(try JSONEncoder().encode(onlyITerm)) == onlyITerm)
    }

    @Test func testSlackRoutesToConfiguredProfileNotLastActiveProfile() {
        let request = LinkRequest(rawURL: "https://example.com/?from=slack#one", sourceBundleID: Router.slackBundleID)
        #expect(Router.route(request, workProfileID: "Profile 1", profiles: profiles) == .automatic(profileID: "Profile 1"))
    }

    @Test func testOtherAppsAndUnknownSourcesAlwaysAskEvenWithOneProfile() {
        for source in [nil, "com.apple.Notes", "com.google.Chrome", "com.tinyspeck.slackmacgap.fake"] {
            let request = LinkRequest(rawURL: "https://example.com", sourceBundleID: source)
            #expect(Router.route(request, workProfileID: "Profile 1", profiles: Array(profiles.suffix(1))) == .picker(message: nil))
        }
    }

    @Test func testMissingWorkProfileAsksWithoutCreatingReplacement() {
        let request = LinkRequest(rawURL: "https://example.com", sourceBundleID: Router.slackBundleID)
        let result = Router.route(request, workProfileID: "Profile 999", profiles: profiles)
        guard case .picker(let message) = result else { Issue.record("Expected picker"); return }
        #expect(message != nil)
    }

    @Test func testUnconfiguredSlackAsks() {
        for selection in [nil, ""] {
            let result = Router.route(LinkRequest(rawURL: "https://example.com", sourceBundleID: Router.slackBundleID), workProfileID: selection, profiles: profiles)
            guard case .picker(let message) = result else { Issue.record("Expected picker"); return }
            #expect(message != nil)
        }
    }

    @Test func testURLIsPreservedExactlyAndShellCharactersRemainArguments() throws {
        let raw = "https://example.com/a%2Fb?x=a%26b&utm_source=test&literal=$(touch%20oops)&q=%22hello%22#part%201"
        let link = try #require(WebLink(raw))
        #expect(link.rawValue == raw)
        #expect(try ChromeArguments.make(profileID: "Profile 1", link: link) == ["--profile-directory=Profile 1", raw])
    }

    @Test func testInvalidAndNonWebURLsAreRejected() {
        for raw in ["", "--incognito", "file:///tmp/test", "javascript:alert(1)", "slack://channel", "https://", "https://a.com/\nfoo", "https://example.com/a b"] {
            #expect(WebLink(raw) == nil)
            #expect(Router.route(LinkRequest(rawURL: raw), workProfileID: "Profile 1", profiles: profiles) == .invalid)
        }
    }

    @Test func testUntrustedProfileDirectoryIsRejected() throws {
        let link = try #require(WebLink("https://example.com"))
        for profile in ["../Default", "/tmp/Profile 1", "Guest Profile", "System Profile", "Profile ", "Profile 1/../../", "--incognito"] {
            #expect(throws: (any Error).self) { try ChromeArguments.make(profileID: profile, link: link) }
        }
    }

    @Test func testParserFiltersDeletedOmittedGuestAndTraversalProfiles() throws {
        let fixture = """
        {"profile":{"info_cache":{
          "Default":{"name":"Personal"},
          "Profile 1":{"name":"Alex (Person 1)"},
          "Profile 2":{"name":"Removed"},
          "Profile 3":{"name":"Omitted","is_omitted":true},
          "Guest Profile":{"name":"Guest"},
          "../escape":{"name":"Escape"}
        }}}
        """
        let result = try ProfileParser.parse(Data(fixture.utf8), root: URL(fileURLWithPath: "/tmp/Chrome"),
                                              existingDirectories: ["Default", "Profile 1", "Profile 3", "Guest Profile", "../escape"])
        #expect(result.map(\.id) == ["Profile 1", "Default"])
    }

    @Test func testRenameKeepsIdentityAndDuplicateNamesAreDistinguished() throws {
        let fixture = """
        {"profile":{"info_cache":{
          "Default":{"name":"Alex","gaia_picture_file_name":"../private"},
          "Profile 1":{"name":"Alex","gaia_picture_file_name":"Google Profile Picture.png"}
        }}}
        """
        let result = try ProfileParser.parse(Data(fixture.utf8), root: URL(fileURLWithPath: "/tmp/Chrome"), existingDirectories: ["Default", "Profile 1"])
        #expect(result.map(\.label) == ["Alex · Default", "Alex · Profile 1"])
        #expect(result[0].avatarPath == nil)
        #expect(result[1].avatarPath == "/tmp/Chrome/Profile 1/Google Profile Picture.png")
        #expect(Router.route(LinkRequest(rawURL: "https://example.com", sourceBundleID: Router.slackBundleID), workProfileID: "Profile 1", profiles: result) == .automatic(profileID: "Profile 1"))
    }

    @Test func testCorruptMetadataFailsRatherThanUsingAnImplicitProfile() {
        for text in ["{", "{}", "{\"profile\":[]}", "{\"profile\":{\"info_cache\":[]}}"] {
            #expect(throws: (any Error).self) { try ProfileParser.parse(Data(text.utf8), root: URL(fileURLWithPath: "/tmp"), existingDirectories: ["Default"]) }
        }
    }

    @Test func testChromeAccountAndLocalNamesMatchProfileMenu() throws {
        let fixture = """
        {"profile":{"info_cache":{
          "Default":{"name":"Alex","gaia_given_name":"Alex","is_using_default_name":false},
          "Profile 1":{"name":"Person 1","gaia_given_name":"Alex","is_using_default_name":true},
          "Profile 2":{"name":"Person 2","gaia_given_name":"Ada","is_using_default_name":true},
          "Profile 3":{"name":"Work","gaia_given_name":"Grace","is_using_default_name":false}
        }}}
        """
        let result = try ProfileParser.parse(Data(fixture.utf8), root: URL(fileURLWithPath: "/tmp/Chrome"), existingDirectories: ["Default", "Profile 1", "Profile 2", "Profile 3"])
        #expect(result.first { $0.id == "Profile 1" }?.name == "Alex (Person 1)")
        #expect(result.first { $0.id == "Default" }?.name == "Alex")
        #expect(result.first { $0.id == "Profile 2" }?.name == "Ada")
        #expect(result.first { $0.id == "Profile 3" }?.name == "Grace (Work)")
    }

    @Test func testQueuePreservesIdenticalClicksAndOrder() {
        let first = LinkRequest(rawURL: "https://example.com")
        let second = LinkRequest(rawURL: "https://example.com")
        var queue = RequestQueue()
        queue.append(PendingRequest(request: first, route: .picker(message: nil)))
        queue.append(PendingRequest(request: second, route: .picker(message: nil)))
        #expect(queue.count == 2)
        queue.removeFirst(id: second.id)
        #expect(queue.first?.request.id == first.id)
        queue.removeFirst(id: first.id)
        #expect(queue.first?.request.id == second.id)
    }

    @Test func testCancellationDiscardsPickerRequestsButRetainsDeferredSlack() {
        let slack = LinkRequest(rawURL: "https://example.com/slack", sourceBundleID: Router.slackBundleID)
        var queue = RequestQueue()
        queue.append(PendingRequest(request: LinkRequest(rawURL: "https://example.com/1"), route: .picker(message: nil)))
        queue.append(PendingRequest(request: slack, route: .automatic(profileID: "Profile 1")))
        queue.append(PendingRequest(request: LinkRequest(rawURL: "https://example.com/2"), route: .picker(message: nil)))
        queue.cancelPickerRequests()
        #expect(queue.count == 1)
        #expect(queue.first?.request.id == slack.id)
    }

    @Test func testAutomaticFailureBecomesCancellablePicker() {
        var queue = RequestQueue()
        queue.append(PendingRequest(request: LinkRequest(rawURL: "https://example.com"), route: .automatic(profileID: "Profile 1")))
        queue.replaceFirstRoute(.picker(message: "Failed"))
        queue.cancelPickerRequests()
        #expect(queue.count == 0)
    }
}
