import Foundation
import MultipeerConnectivity
import UIKit

// MARK: - Remote Client (iOS 쪽)
//
// 주변에서 StickyPresenter 를 광고하는 Mac 을 찾아 붙고, 명령을 보내고, 상태를 받는다.
// Mac 쪽(RemoteControlHost)이 광고자(advertiser), 이쪽이 탐색자(browser) 역할이다.

@MainActor
final class RemoteClient: NSObject, ObservableObject {

    enum Status: Equatable {
        case searching
        case connecting(String)
        case connected(String)
        case failed(String)

        var label: String {
            switch self {
            case .searching:            return "Mac 찾는 중…"
            case .connecting(let name): return "\(name)에 연결 중…"
            case .connected(let name):  return name
            case .failed(let message):  return message
            }
        }
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var timers: [RemoteTimer] = []

    private let peerID = MCPeerID(displayName: String(UIDevice.current.name.prefix(30)))
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    /// 이미 초대장을 보낸 상대. 브라우저가 같은 피어를 여러 번 알려줄 수 있어
    /// 중복 초대를 막지 않으면 세션이 서로를 밀어내며 연결이 불안정해진다.
    private var invited = Set<MCPeerID>()

    // MARK: 수명주기

    func start() {
        guard session == nil else { return }

        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: RemoteService.type)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        status = .searching
    }

    func stop() {
        browser?.stopBrowsingForPeers(); browser = nil
        session?.disconnect(); session = nil
        invited.removeAll()
        timers = []
        status = .searching
    }

    // MARK: 명령 송신

    func send(_ command: RemoteCommand) {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? RemotePacket.command(command).encoded() else { return }
        // 명령은 유실되면 안 된다 — 상태와 달리 재전송해 주는 후속 패킷이 없다.
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension RemoteClient: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard let session = self.session, !self.invited.contains(peerID) else { return }
            self.invited.insert(peerID)
            self.status = .connecting(peerID.displayName)
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.invited.remove(peerID)
            if self.session?.connectedPeers.isEmpty ?? true {
                self.timers = []
                self.status = .searching
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            // 로컬 네트워크 권한을 거부하면 여기로 떨어진다.
            self.status = .failed("검색 실패 — 설정 > 개인정보 보호에서 로컬 네트워크 권한을 확인하세요")
        }
    }
}

// MARK: - MCSessionDelegate

extension RemoteClient: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.status = .connected(peerID.displayName)
                self.send(.requestState)   // 1초 주기를 기다리지 않고 즉시 첫 상태를 받는다
            case .connecting:
                self.status = .connecting(peerID.displayName)
            case .notConnected:
                self.invited.remove(peerID)
                if session.connectedPeers.isEmpty {
                    self.timers = []
                    self.status = .searching
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = try? RemotePacket.decode(data),
              case .state(let state) = packet else { return }
        Task { @MainActor in
            self.timers = state.timers
            self.status = .connected(state.hostName)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
