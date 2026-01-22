//
//  ScaleLibraryStoreTests.swift
//  TenneyTests
//
//  Created by Sebastian Suarez-Solis on 10/6/25.
//

import Foundation
import Testing
@testable import Tenney

@MainActor
private func withStoreStateRestored(_ action: (ScaleLibraryStore) -> Void) {
    let store = ScaleLibraryStore.shared
    let originalScales = store.scales
    let originalSortKey = store.sortKey
    let originalFavorites = store.favoriteIDs
    let originalFavoritesData = UserDefaults.standard.data(forKey: SettingsKeys.libraryFavoriteIDsJSON)
    let originalRecentPacksData = UserDefaults.standard.data(forKey: SettingsKeys.libraryRecentPackIDsJSON)

    defer {
        store.scales = originalScales
        store.sortKey = originalSortKey
        for id in store.favoriteIDs {
            store.setFavorite(false, for: id)
        }
        for id in originalFavorites {
            store.setFavorite(true, for: id)
        }
        if let data = originalFavoritesData {
            UserDefaults.standard.set(data, forKey: SettingsKeys.libraryFavoriteIDsJSON)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.libraryFavoriteIDsJSON)
        }
        if let data = originalRecentPacksData {
            UserDefaults.standard.set(data, forKey: SettingsKeys.libraryRecentPackIDsJSON)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.libraryRecentPackIDsJSON)
        }
    }

    action(store)
}

struct ScaleLibraryStoreTests {
    @Test @MainActor func favoritesPersistByID() {
        withStoreStateRestored { store in
            let scale = TenneyScale(name: "Test Scale", degrees: [RatioRef(p: 1, q: 1)])
            store.scales = [scale.id: scale]

            store.setFavorite(true, for: scale.id)

            #expect(store.isFavorite(id: scale.id))
            let data = UserDefaults.standard.data(forKey: SettingsKeys.libraryFavoriteIDsJSON)
            #expect(data != nil)
            if let data {
                let decoded = try? JSONDecoder().decode([UUID].self, from: data)
                #expect(decoded?.contains(scale.id) == true)
            }
        }
    }

    @Test @MainActor func moveScaleAssignsAndClearsPack() {
        withStoreStateRestored { store in
            let packA = PackRef(source: .user, id: "user:a", title: "Alpha", slug: nil)
            let packB = PackRef(source: .user, id: "user:b", title: "Beta", slug: nil)
            let scale = TenneyScale(name: "Mover", degrees: [RatioRef(p: 1, q: 1)], pack: packA)
            store.scales = [scale.id: scale]

            let outcome = store.moveScale(id: scale.id, to: packB)
            #expect(outcome == .moved(previous: packA, current: packB))
            #expect(store.scales[scale.id]?.pack?.id == packB.id)

            let cleared = store.moveScale(id: scale.id, to: nil)
            #expect(cleared == .moved(previous: packB, current: nil))
            #expect(store.scales[scale.id]?.pack == nil)
        }
    }

    @Test @MainActor func duplicateScaleCreatesUserCopy() {
        withStoreStateRestored { store in
            let provenance = TenneyScale.Provenance(
                kind: .communityPack,
                packID: "community:demo",
                packName: "Community Demo",
                authorName: "Author",
                installedVersion: "1.0"
            )
            let scale = TenneyScale(
                name: "Community Scale",
                degrees: [RatioRef(p: 1, q: 1)],
                provenance: provenance,
                pack: PackRef(source: .community, id: "community:demo", title: "Community Demo", slug: "demo")
            )
            store.scales = [scale.id: scale]

            let newID = store.duplicateScaleToUser(id: scale.id)
            #expect(newID != nil)
            if let newID, let duplicated = store.scales[newID] {
                #expect(duplicated.id != scale.id)
                #expect(duplicated.provenance == nil)
                #expect(duplicated.pack == nil)
                #expect(duplicated.name != scale.name)
            }
        }
    }
}
