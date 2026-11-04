//
//  WhatsNewManager.swift
//  DoMemory
//

import SwiftUI

/// Tracks whether the What's New sheet should be presented for the current app version.
///
/// On a brand-new install the current version is stored immediately so first-time users
/// never see the sheet. On updates `shouldShow` starts as `true` only while the stored
/// version is older than `releaseNotesVersion`, the release the sheet's content describes;
/// calling `markSeen()` persists the running version and hides the sheet.
@MainActor
final class WhatsNewManager: ObservableObject {
    /// The release whose features `WhatsNew.current` lists. A version that changes nothing
    /// worth announcing (4.5.0: fixes and improvements) leaves this alone, so players who
    /// already read these notes are not shown them again under a new number. **Raise it
    /// in the same change that rewrites the sheet's items**, or the new notes reach no one
    /// who has seen the old ones.
    nonisolated static let releaseNotesVersion = "4.6.0"

    @Published var shouldShow: Bool = false

    private let defaults: UserDefaults

    /// - Parameter isExistingUser: whether this install has played before. A missing
    ///   stored version cannot tell us that on its own — someone upgrading from a build
    ///   that predates this manager has no stored version either, and they *should* see
    ///   the sheet. Onboarding state is what separates the two.
    /// - Parameter releaseNotesVersion: injectable for tests; defaults to the shipped notes.
    init(
        defaults: UserDefaults = .standard,
        isExistingUser: Bool,
        releaseNotesVersion: String = WhatsNewManager.releaseNotesVersion
    ) {
        self.defaults = defaults

        // A first launch has nothing to announce: the "new" features are simply the
        // app. Record the running version so the sheet stays quiet until a real
        // upgrade happens, rather than greeting a brand-new player with release
        // notes for a version they have never not had.
        guard isExistingUser else {
            defaults.set(Self.currentVersion, forKey: UserDefaultsKeys.whatsNewLastSeenVersion)
            shouldShow = false
            return
        }

        let seen = defaults.string(forKey: UserDefaultsKeys.whatsNewLastSeenVersion)
        shouldShow = Self.hasUnreadNotes(seen: seen, releaseNotesVersion: releaseNotesVersion)
        if shouldShow, let version = Self.currentVersion {
            AnalyticsService.log(.whatsNewShown(version: version))
        }
    }

    /// True when the player last saw the sheet before the release it describes, or has no
    /// record at all (an upgrade from a build that predates this manager). Compared
    /// numerically, so "4.10.0" is newer than "4.9.0".
    nonisolated static func hasUnreadNotes(seen: String?, releaseNotesVersion: String) -> Bool {
        guard let seen else { return true }
        return seen.compare(releaseNotesVersion, options: .numeric) == .orderedAscending
    }

    /// Call this from the sheet's dismiss closure.
    func markSeen() {
        if let version = Self.currentVersion {
            AnalyticsService.log(.whatsNewDismissed(version: version))
        }
        defaults.set(Self.currentVersion, forKey: UserDefaultsKeys.whatsNewLastSeenVersion)
        shouldShow = false
    }

    private static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    #if DEBUG
    /// Resets the stored version so the sheet appears again on next launch.
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.whatsNewLastSeenVersion)
    }
    #endif
}
