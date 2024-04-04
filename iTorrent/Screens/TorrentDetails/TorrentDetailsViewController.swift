//
//  TorrentDetailsViewController.swift
//  iTorrent
//
//  Created by Daniil Vinogradov on 30/10/2023.
//

import MarqueeLabel
import MvvmFoundation
import SwiftUI

class TorrentDetailsViewController<VM: TorrentDetailsViewModel>: BaseViewController<VM> {
    @IBOutlet private var collectionView: MvvmCollectionView!

    private let shareButton = UIBarButtonItem(title: "Share", image: .init(systemName: "square.and.arrow.up"))
    private let playButton = UIBarButtonItem()
    private let pauseButton = UIBarButtonItem()

    private let titleLabel = MarqueeLabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.title
        navigationItem.largeTitleDisplayMode = .never

        disposeBag.bind {
            viewModel.dismissSignal.sink { [unowned self] _ in
                guard !((splitViewController as? BaseSplitViewController)?.showEmptyDetail() ?? false)
                else { return }

                pop(animated: true, sender: self)
            }

            viewModel.$sections.sink { [unowned self] sections in
                if collectionView.diffDataSource.snapshot().sectionIdentifiers.differs(from: sections) {
                    collectionView.diffDataSource.applyModels(sections)
                }
            }

            viewModel.shareAvailable.sink { [unowned self] available in
                shareButton.isEnabled = available
            }

            viewModel.$isPaused.sink { [unowned self] isPaused in
                playButton.isEnabled = isPaused
                pauseButton.isEnabled = !isPaused
            }
        }

        playButton.primaryAction = .init(title: "Start", image: .init(systemName: "play.fill"), handler: { [unowned self] _ in
            viewModel.resume()
        })

        pauseButton.primaryAction = .init(title: "Pause", image: .init(systemName: "pause.fill"), handler: { [unowned self] _ in
            viewModel.pause()
        })

        shareButton.menu = .init(title: "Share", children: [
            UIAction(title: "Torrent file", image: .init(systemName: "doc"), handler: { [unowned self] _ in
                guard let path = viewModel.torrentFilePath
                else { return }

                let url = NSURL(fileURLWithPath: path, isDirectory: false)
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if vc.popoverPresentationController != nil {
                    vc.popoverPresentationController?.barButtonItem = shareButton
                    vc.popoverPresentationController?.permittedArrowDirections = .any
                }
                present(vc, animated: true)
            }),
            UIAction(title: "Magnet link", image: .init(systemName: "link"), handler: { [unowned self] _ in
                viewModel.shareMagnet()
            })
        ])
        navigationItem.trailingItemGroups.append(.fixedGroup(items: [shareButton]))

        toolbarItems = [
            playButton,
            fixedSpacing,
            pauseButton,
            fixedSpacing,
            .init(title: "Rehash", image: .init(systemName: "arrow.clockwise"), primaryAction: .init(handler: { [unowned self] _ in
                viewModel.rehash()
            })),
            .init(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            .init(title: "Delete", image: .init(systemName: "trash"), primaryAction: .init(handler: { [unowned self] _ in
                viewModel.removeTorrent()
            }))
        ]

#if !os(visionOS)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
#else
        titleLabel.font = .preferredFont(forTextStyle: .title1)
#endif
        titleLabel.fadeLength = 16
        titleLabel.text = title
        titleLabel.adjustsFontForContentSizeCategory = true

#if !os(visionOS) // Not renders properly on VisionOS
        navigationItem.titleView = titleLabel
#endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        smoothlyDeselectRows(in: collectionView)
    }
}

extension Array where Element == MvvmCollectionSectionModel {
    func differs(from sections: [MvvmCollectionSectionModel]) -> Bool {
        var needUpdate = false
        let diff = difference(from: sections)
        if !diff.insertions.isEmpty || !diff.removals.isEmpty {
            needUpdate = true
        }
        if !needUpdate {
            for section in enumerated() {
                let diff = section.element.items.difference(from: sections[section.offset].items)
                if !diff.insertions.isEmpty || !diff.removals.isEmpty {
                    needUpdate = true
                }
            }
        }
        return needUpdate
    }
}

private extension TorrentDetailsViewController {
    var fixedSpacing: UIBarButtonItem {
        let item = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        item.width = 44
        return item
    }
}