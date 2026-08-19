import Foundation
import MultipeerConnectivity
import AppKit

// MARK: - Remote Control Host (Mac 쪽)
//
// iOS 리모컨 앱이 붙을 수 있도록 자신을 광고하고, 들어온 명령을 실제 타이머에 적용한다.
// 상태는 1초마다 전체를 브로드캐스트한다 — 델타 동기화는 타이머가 몇 개 없는 이 앱에서
// 복잡도만 늘리고, 패킷을 하나 놓쳐도 다음 초에 저절로 복구되는 편이 훨씬 튼튼하다.
//
// 샌드박스 앱이라 entitlements 에 network.client / network.server 가,
// Info.plist 에 NSBonjourServices 와 NSLocalNetworkUsageDescription 이 있어야 동작한다.

@MainActor
final class RemoteControlHost: NSObject, ObservableObject {
    static let shared = RemoteControlHost()

    /// 지금 붙어 있는 리모컨 수 — 메뉴/UI에서 연결 상태를 보여주는 데 쓴다.
    @Published private(set) var connectedCount = 0

    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var broadcastTimer: Foundation.Timer?

    private override init() {
        let name = Host.current().localizedName ?? "Mac"
        // MCPeerID displayName 은 63바이트 제한이 있다. 긴 컴퓨터 이름에서 터진다.
        self.peerID = MCPeerID(displayName: String(name.prefix(30)))
        super.init()
    }

    // MARK: 수명주기

    func start() {
        guard session == nil else { return }

        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID, discoveryInfo: nil, serviceType: RemoteService.type
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        // 1초 주기 — 타이머 표시가 초 단위라 그보다 자주 보낼 이유가 없다.
        let timer = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.broadcastState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        broadcastTimer = timer
    }

    func stop() {
        broadcastTimer?.invalidate(); broadcastTimer = nil
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        session?.disconnect(); session = nil
        connectedCount = 0
    }

    // MARK: 상태 송신

    /// 타이머가 바뀌는 즉시 반영하고 싶을 때 호출 (1초 주기를 기다리지 않도록).
    func pushStateNow() { broadcastState() }

    private func broadcastState() {
        guard let session, !session.connectedPeers.isEmpty else { return }

        let timers = NoteManager.shared.timerListManager.entries.map { entry in
            RemoteTimer(
                id: entry.id,
                name: entry.name,
                remaining: entry.remaining,
                target: entry.targetSeconds,
                isRunning: entry.isRunning,
                isFinished: entry.isFinished,
                isHidden: entry.isWidgetHidden,
                isPomodoro: entry.isPomodoro,
                phaseTitle: entry.isPomodoro ? entry.phase.title : nil,
                cycleNumber: entry.cycleNumber,
                size: entry.widgetSize.rawValue,
                theme: entry.theme.rawValue
            )
        }
        let packet = RemotePacket.state(RemoteState(hostName: peerID.displayName, timers: timers))
        send(packet, to: session.connectedPeers)
    }

    private func send(_ packet: RemotePacket, to peers: [MCPeerID]) {
        guard let session, !peers.isEmpty, let data = try? packet.encoded() else { return }
        // .unreliable — 매초 전체 상태를 다시 보내므로 유실돼도 다음 패킷이 덮어쓴다.
        // 재전송을 기다리다 밀리는 것보다 최신 상태가 빨리 도착하는 편이 낫다.
        try? session.send(data, toPeers: peers, with: .unreliable)
    }

    // MARK: 명령 적용

    private func apply(_ command: RemoteCommand) {
        let manager = NoteManager.shared
        let entries = manager.timerListManager.entries
        func entry(_ id: UUID) -> TimerEntry? { entries.first { $0.id == id } }

        switch command {
        case .requestState:
            broadcastState()

        case .toggleRun(let id):
            guard let e = entry(id) else { return }
            // 완료된 타이머를 다시 누르면 되감고 시작 — 패널의 재생 버튼과 같은 동작.
            if e.isFinished { e.reset() }
            e.toggleRunning()

        case .addSeconds(let id):      entry(id)?.addSeconds()
        case .subtractSeconds(let id): entry(id)?.subtractSeconds()
        case .reset(let id):           entry(id)?.reset()

        case .setSize(let id, let raw):
            guard let e = entry(id), let size = WidgetSize(rawValue: raw) else { return }
            manager.setWidgetSize(size, for: e)

        case .cycleTheme(let id):
            guard let e = entry(id) else { return }
            e.theme = e.theme.next

        case .toggleHidden(let id):
            guard let e = entry(id) else { return }
            if e.isWidgetHidden {
                e.widgetPanel?.orderFront(nil)
                e.isWidgetHidden = false
            } else {
                e.widgetPanel?.orderOut(nil)
                e.isWidgetHidden = true
            }

        case .align(let id):
            guard let e = entry(id) else { return }
            manager.snapWidgetToPanel(for: e)

        case .remove(let id):
            guard let e = entry(id) else { return }
            manager.timerListManager.remove(e)

        case .addPreset(let seconds, let name):
            let e = TimerEntry(name: name, targetSeconds: seconds)
            e.setRunning(true)
            manager.timerListManager.add(e)
        }

        // 명령 결과가 리모컨에 곧바로 보이도록 즉시 되돌려준다.
        broadcastState()
    }
}

// MARK: - MCSessionDelegate

extension RemoteControlHost: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedCount = session.connectedPeers.count
            if state == .connected { self.broadcastState() }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = try? RemotePacket.decode(data) else { return }
        // 리모컨이 상태를 보내오는 일은 없다. 명령만 처리한다.
        guard case .command(let command) = packet else { return }
        Task { @MainActor in self.apply(command) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension RemoteControlHost: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 같은 로컬 네트워크에 있고 서비스 타입까지 맞는 상대만 여기 도달한다.
        // 발표 직전에 수락 다이얼로그를 띄우는 건 오히려 방해가 되므로 자동 수락한다.
        Task { @MainActor in invitationHandler(true, self.session) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: Error) {
        NSLog("[Remote] 광고 시작 실패: \(error.localizedDescription)")
    }
}
