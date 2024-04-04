//
//  TorrentService.swift
//  iTorrent
//
//  Created by Daniil Vinogradov on 29/10/2023.
//

import Combine
import LibTorrent
import MvvmFoundation

extension TorrentService {
    struct TorrentUpdateModel {
        let oldSnapshot: TorrentHandle.Snapshot
        let handle: TorrentHandle
    }
}

class TorrentService {
    @Published var torrents: [TorrentHandle] = []
    var updateNotifier = PassthroughSubject<TorrentUpdateModel, Never>()

    static let shared = TorrentService()
    static var version: String { Version.libtorrentVersion }

    init() { setup() }

    static var downloadPath: URL { try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) }
    static var torrentPath: URL { downloadPath.appending(path: "config") }
    static var fastResumePath: URL { downloadPath.appending(path: "config") }
    static var metadataPath: URL { downloadPath.appending(path: "config") }

    private let session: Session = {
        var settings = Session.Settings()
        print("Working directory: \(downloadPath.path())")
        return .init(downloadPath.path(), torrentsPath: torrentPath.path(), fastResumePath: fastResumePath.path(), settings: .fromPreferences(with: []))
    }()

    private let disposeBag = DisposeBag()

    @Injected private var network: NetworkMonitoringService
    @Injected private var preferences: PreferencesStorage
}

extension TorrentService {
    func addTorrent(by file: Downloadable) {
        guard !torrents.contains(where: { file.infoHashes == $0.infoHashes })
        else { return }

        session.addTorrent(file)
    }

    func addTorrent(by path: URL) {
        defer { path.stopAccessingSecurityScopedResource() }
        guard path.startAccessingSecurityScopedResource(),
              let file = TorrentFile(with: path)
        else { return }

        guard !torrents.contains(where: { file.infoHashes == $0.infoHashes })
        else { return }

        session.addTorrent(file)
    }

    func removeTorrent(by infoHashes: TorrentHashes, deleteFiles: Bool) {
        guard let handle = torrents.first(where: { $0.infoHashes == infoHashes })
        else { return }

        handle.deleteMetadata()
        session.removeTorrent(handle, deleteFiles: deleteFiles)
    }

    func updateSettings(_ settings: Session.Settings) {
        session.settings = settings
    }
}

extension TorrentService: SessionDelegate {
    func torrentManager(_ manager: Session, didAddTorrent torrent: TorrentHandle) {
        guard torrents.firstIndex(where: { $0.infoHashes == torrent.infoHashes }) == nil
        else { return }

        _ = torrent.metadata
        torrent.updateSnapshot()
        
        DispatchQueue.main.sync { [self] in
            torrents.append(torrent)
        }
    }

    func torrentManager(_ manager: Session, didRemoveTorrentWithHash hashesData: TorrentHashes) {
        // Already on Main thread
        guard let index = torrents.firstIndex(where: { $0.infoHashes == hashesData })
        else { return }

        let torrent = torrents[index]
        torrent.removePublisher.send(torrent)
        torrents.remove(at: index)
    }

    func torrentManager(_ manager: Session, didReceiveUpdateForTorrent torrent: TorrentHandle) {
        guard let existingTorrent = torrents.first(where: { $0.infoHashes == torrent.infoHashes })
        else { return }

        let oldSnapshot = existingTorrent.snapshot
        existingTorrent.updateSnapshot()
        updateNotifier.send(.init(oldSnapshot: oldSnapshot, handle: existingTorrent))

        DispatchQueue.main.sync {
            existingTorrent.updatePublisher.send(existingTorrent)
        }
    }

    func torrentManager(_ manager: Session, didErrorOccur error: Error) {}
}

private extension TorrentService {
    func setup() {
        torrents = session.torrents.map { torrent in
            _ = torrent.metadata
            torrent.updateSnapshot()
            return torrent
        }
        session.add(self)

        disposeBag.bind {
            preferences.settingsUpdatePublisher
                .combineLatest(network.$availableInterfaces)
                .sink { [unowned self] _, interfaces in
                    DispatchQueue.main.async { [self] in // Need delay to complete settings apply
                        session.settings = Session.Settings.fromPreferences(with: interfaces.map { $0.name })
                    }
                }
        }
    }
}