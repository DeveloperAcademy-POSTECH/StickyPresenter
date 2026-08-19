import Foundation

// MARK: - Remote Control Protocol
// Mac 앱(StickyPresenter)과 iOS 리모컨 앱이 MultipeerConnectivity 로 주고받는 규약.
// **이 파일은 두 프로젝트가 같은 파일을 참조한다.** 한쪽만 고치면 디코딩이 깨지므로
// 필드를 바꿀 때는 반드시 양쪽을 같이 빌드해 확인할 것.

public enum RemoteService {
    /// MultipeerConnectivity 서비스 타입.
    /// 1~15자, 소문자·숫자·하이픈만 허용된다는 제약이 있어 짧게 잡았다.
    /// Info.plist 의 NSBonjourServices 에도 `_sp-timer._tcp` / `._udp` 로 같이 올라가 있어야 한다.
    public static let type = "sp-timer"
}

// MARK: - 상태 (Mac → iOS)

/// 리모컨 화면에 타이머 하나를 그리는 데 필요한 값 전부.
/// Mac 의 `TimerEntry` 를 그대로 보내지 않고 납작한 값 타입으로 옮겨 담는다 —
/// `TimerEntry` 는 창·티커 같은 로컬 자원을 들고 있어 직렬화 대상이 아니다.
public struct RemoteTimer: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var remaining: TimeInterval
    public var target: TimeInterval
    public var isRunning: Bool
    public var isFinished: Bool
    public var isHidden: Bool
    public var isPomodoro: Bool
    /// 뽀모도로일 때만 채워진다 ("Focus" / "Break").
    public var phaseTitle: String?
    public var cycleNumber: Int
    /// `WidgetSize.rawValue` — "S" / "M" / "L"
    public var size: String
    /// `WidgetTheme.rawValue` — "system" / "light" / "dark" / "chameleon"
    public var theme: String

    public init(id: UUID, name: String, remaining: TimeInterval, target: TimeInterval,
                isRunning: Bool, isFinished: Bool, isHidden: Bool, isPomodoro: Bool,
                phaseTitle: String?, cycleNumber: Int, size: String, theme: String) {
        self.id = id; self.name = name
        self.remaining = remaining; self.target = target
        self.isRunning = isRunning; self.isFinished = isFinished; self.isHidden = isHidden
        self.isPomodoro = isPomodoro; self.phaseTitle = phaseTitle; self.cycleNumber = cycleNumber
        self.size = size; self.theme = theme
    }

    public var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, (target - remaining) / target))
    }
}

/// Mac 이 주기적으로(그리고 변화가 있을 때마다) 뿌리는 전체 상태.
/// 델타가 아니라 전체를 보낸다 — 타이머가 몇 개 없어서 비용이 무의미하고,
/// 패킷을 하나 놓쳐도 다음 갱신에서 저절로 복구된다.
public struct RemoteState: Codable, Sendable {
    public var hostName: String
    public var timers: [RemoteTimer]

    public init(hostName: String, timers: [RemoteTimer]) {
        self.hostName = hostName
        self.timers = timers
    }
}

// MARK: - 명령 (iOS → Mac)

public enum RemoteCommand: Codable, Sendable {
    /// 재생/일시정지. 완료된 타이머면 Mac 쪽에서 reset 후 시작한다 (패널 버튼과 동일 동작).
    case toggleRun(UUID)
    case addSeconds(UUID)
    case subtractSeconds(UUID)
    case reset(UUID)
    /// `WidgetSize.rawValue`
    case setSize(UUID, String)
    /// 테마를 다음 것으로 순환
    case cycleTheme(UUID)
    /// 위젯 창 감추기/보이기
    case toggleHidden(UUID)
    /// 위젯을 패널 옆으로 정렬 (화면 밖으로 나갔을 때 되찾기)
    case align(UUID)
    case remove(UUID)
    /// 프리셋으로 새 타이머 추가 (3m/5m/10m/15m)
    case addPreset(seconds: Double, name: String)
    /// 연결 직후 현재 상태를 즉시 달라는 요청
    case requestState
}

// MARK: - 봉투
// 명령과 상태를 한 채널로 흘려보내기 위한 최소한의 구분자.

public enum RemotePacket: Codable, Sendable {
    case state(RemoteState)
    case command(RemoteCommand)

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> RemotePacket {
        try JSONDecoder().decode(RemotePacket.self, from: data)
    }
}
