import SwiftUI
import UIKit

@main
struct StickyPresenterRemoteApp: App {
    @StateObject private var client = RemoteClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RemoteRootView()
                .environmentObject(client)
                .onAppear { client.start() }
                .onChange(of: scenePhase) { _, phase in
                    // 백그라운드에서 세션을 붙들고 있으면 iOS 가 곧 끊어버리고,
                    // 복귀했을 때 죽은 세션으로 계속 시도하게 된다. 깨끗이 끊고 다시 찾는다.
                    switch phase {
                    case .active:     client.start()
                    case .background: client.stop()
                    default:          break
                    }
                }
        }
    }
}

// MARK: - Root

struct RemoteRootView: View {
    @EnvironmentObject private var client: RemoteClient

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Remote Controller")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { statusDot }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !client.isConnected {
            DisconnectedView()
        } else if client.timers.isEmpty {
            EmptyTimersView()
        } else {
            List {
                ForEach(client.timers) { timer in
                    Section { TimerRemoteRow(timer: timer) }
                }
                Section("새 타이머") {
                    PresetRow()
                        .padding(.vertical, 4)
                }
            }
            .listSectionSpacing(.compact)
        }
    }

    /// 연결 상태는 점 하나로만 알린다.
    /// 상태 문구까지 툴바에 넣으면 기기 이름이 길 때 제목을 밀어내고 잘린다.
    private var statusDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(client.isConnected ? .green : .orange)
                .frame(width: 8, height: 8)
            if case .connected(let name) = client.status {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
        }
    }
}

// MARK: - Empty

/// 연결은 됐는데 타이머가 하나도 없을 때.
///
/// `ContentUnavailableView` 의 `actions` 슬롯을 쓰다 걷어냈다. 그 슬롯은 폭을 좁게 잡아
/// (402pt 화면에서 230pt 남짓) 프리셋 4개를 넣으면 글자 크기를 조금만 키워도
/// "10분" 이 "1…" 로 잘린다. 버튼이 화면 폭을 다 쓰게 하려면 직접 짜는 수밖에 없다.
/// 생김새는 `DisconnectedView` 의 머리말과 같은 방식이라 둘이 따로 놀지 않는다.
struct EmptyTimersView: View {
    var body: some View {
        // 글자를 크게 쓰면 프리셋이 한 열로 내려가면서 화면보다 길어진다.
        // 화면 높이만큼을 최소 높이로 준 뒤 스크롤에 담으면, 들어갈 때는 가운데 정렬로 보이고
        // 넘칠 때만 스크롤이 생긴다 (`DisconnectedView` 가 스크롤을 쓰는 것과 같은 이유).
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text("실행 중인 타이머 없음")
                        .font(.title3.weight(.semibold))

                    Text("아래에서 시간을 골라 시작하세요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    PresetRow()
                        .padding(.top, 8)
                }
                .multilineTextAlignment(.center)
                // 글자를 키우면 안내 문구가 두 줄로 흐른다. 잘리지 않게 세로로 늘어나도록 둔다.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height - 48)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Disconnected

/// 연결이 안 됐을 때 **무엇을 확인해야 하는지**까지 같이 보여준다.
/// MultipeerConnectivity 는 실패해도 원인을 알려주지 않아서, 상태 문구만 띄우면
/// 사용자가 손댈 곳을 찾지 못한다. 실제로 걸리는 지점들을 순서대로 나열한다.
struct DisconnectedView: View {
    @EnvironmentObject private var client: RemoteClient

    private struct Check: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private var checks: [Check] {
        [
            Check(symbol: "menubar.arrow.up.rectangle",
                  title: "Mac에서 StickyPresenter가 켜져 있나요?",
                  detail: "메뉴 막대에 타이머 아이콘이 보여야 합니다. 창을 모두 닫아도 앱은 메뉴 막대에 남아 있습니다."),
            Check(symbol: "wifi",
                  title: "두 기기가 같은 Wi-Fi인가요?",
                  detail: "네트워크가 다르거나 게스트 Wi-Fi에 붙어 있으면 서로를 찾지 못합니다."),
            Check(symbol: "lock.shield",
                  title: "iPhone의 로컬 네트워크 접근을 허용했나요?",
                  detail: "설정 → 개인정보 보호 및 보안 → 로컬 네트워크에서 Remote Controller를 켜주세요."),
            Check(symbol: "desktopcomputer",
                  title: "Mac에서도 허용이 필요할 수 있어요",
                  detail: "시스템 설정 → 개인정보 보호 및 보안 → 로컬 네트워크에서 StickyPresenter를 확인하세요."),
            Check(symbol: "network.badge.shield.half.filled",
                  title: "VPN을 쓰고 있나요?",
                  detail: "VPN이 켜져 있으면 같은 네트워크의 기기를 찾지 못할 수 있습니다. 잠시 꺼보세요.")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                checklist
                settingsButton
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: isFailed ? "exclamationmark.triangle" : "wifi.slash")
                .font(.system(size: 42, weight: .light))
                // 삼항으로 섞으면 Color 와 계층 스타일의 타입이 달라 컴파일되지 않는다.
                .foregroundStyle(isFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                .symbolEffect(.pulse, isActive: !isFailed)

            Text(isFailed ? "연결할 수 없습니다" : "Mac을 찾는 중")
                .font(.title3.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
    }

    /// 제목이 이미 "찾는 중"이라고 말하므로 상태 문구를 그대로 되풀이하지 않는다.
    /// 상태마다 제목이 담지 못하는 정보만 덧붙인다.
    private var subtitle: String {
        switch client.status {
        case .searching:
            return "주변에서 StickyPresenter가 켜진 Mac을 찾고 있습니다"
        case .connecting(let name):
            return "\(name)에 연결하는 중입니다"
        case .failed(let message):
            return message
        case .connected:
            return ""
        }
    }

    private var isFailed: Bool {
        if case .failed = client.status { return true }
        return false
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("확인해 보세요")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                if index > 0 {
                    Divider().padding(.vertical, 12)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.symbol)
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 24, alignment: .center)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.title)
                            .font(.subheadline.weight(.medium))
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // 두 줄 이상으로 흐르는 설명이 잘리지 않게 한다.
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var settingsButton: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            Label("iPhone 설정 열기", systemImage: "gear")
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Presets

struct PresetRow: View {
    @EnvironmentObject private var client: RemoteClient

    /// 버튼 하나가 글자를 자르지 않고 담을 수 있는 최소 폭.
    /// `@ScaledMetric` 이라 글자 크기 설정을 따라 같이 커진다 — 이게 핵심이다.
    /// 고정값이면 큰 글자에서도 4개가 한 줄에 남아 "10분" 이 "1…" 로 잘린다.
    @ScaledMetric(relativeTo: .subheadline) private var minButtonWidth: CGFloat = 74

    /// (버튼에 보일 글자, 타이머 이름, 초).
    /// 이름은 Mac 앱의 프리셋과 **같은 표기**를 쓴다 — 여기서 "5분"으로 만들면
    /// Mac 목록과 알림 센터 위젯에 "5m"과 "5분"이 섞여 보인다.
    private static let presets: [(label: String, name: String, seconds: Double)] =
        [("3분", "3m", 180), ("5분", "5m", 300), ("10분", "10m", 600), ("15분", "15m", 900)]

    var body: some View {
        // 들어갈 만큼만 한 줄에 놓고 나머지는 다음 줄로 접는다.
        // 기본 글자 크기면 4개가 한 줄, 크게 키우면 2×2, 더 키우면 한 열로 내려간다.
        // 억지로 한 줄에 맞춰 글자를 줄이면 결국 읽을 수 없게 되는데,
        // 프리셋은 눌러야 하는 버튼이라 줄 수를 늘리더라도 읽히는 쪽이 먼저다.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minButtonWidth), spacing: 8)],
                  spacing: 8) {
            ForEach(Self.presets, id: \.name) { preset in
                Button {
                    client.send(.addPreset(seconds: preset.seconds, name: preset.name))
                } label: {
                    Text(preset.label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(!client.isConnected)
    }
}

// MARK: - Timer Row

struct TimerRemoteRow: View {
    @EnvironmentObject private var client: RemoteClient
    let timer: RemoteTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            timeAndProgress
            transport
            sizePicker
            positionPad
            secondaryActions
        }
        .padding(.vertical, 6)
    }

    // MARK: 머리말

    private var header: some View {
        HStack(spacing: 8) {
            if timer.isPomodoro, let phase = timer.phaseTitle {
                Label("\(phase) · #\(timer.cycleNumber)", systemImage: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            } else {
                Text(timer.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if timer.isFinished {
                Text("완료")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.red))
            } else if timer.isHidden {
                Label("감춤", systemImage: "eye.slash.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }

    // MARK: 남은 시간

    private var timeAndProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(format(timer.remaining))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // 1시간이 넘으면 자릿수가 늘어난다. 줄바꿈 대신 줄여서 한 줄을 지킨다.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.3), value: timer.remaining)

                Spacer(minLength: 8)

                Text("\(Int(timer.progress * 100))%")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: timer.progress)
                .tint(timer.isFinished ? .red : .accentColor)
        }
    }

    // MARK: 재생 제어

    private var transport: some View {
        HStack(spacing: 10) {
            // 아이콘으로 두면 좁은 화면에서도 글자가 깨지지 않고 뜻이 바로 읽힌다.
            circleButton("gobackward.30", label: "30초 빼기") {
                client.send(.subtractSeconds(timer.id))
            }

            Button {
                client.send(.toggleRun(timer.id))
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(timer.isRunning ? "일시정지" : "시작")

            circleButton("goforward.30", label: "30초 더하기") {
                client.send(.addSeconds(timer.id))
            }
        }
    }

    private func circleButton(_ symbol: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 56, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }

    // MARK: 창 크기

    private var sizePicker: some View {
        // 세그먼트 컨트롤이라 버튼 세 개를 나란히 두는 것보다 폭을 적게 먹고
        // 현재 선택도 한눈에 보인다.
        Picker("창 크기", selection: sizeBinding) {
            Text("S").tag("S")
            Text("M").tag("M")
            Text("L").tag("L")
        }
        .pickerStyle(.segmented)
    }

    /// 선택 즉시 Mac 으로 명령을 보낸다. 실제 값은 다음 상태 갱신 때 되돌아온다.
    private var sizeBinding: Binding<String> {
        Binding(
            get: { timer.size },
            set: { client.send(.setSize(timer.id, $0)) }
        )
    }

    // MARK: 창 위치

    private var positionPad: some View {
        WidgetPositionPad(desktop: client.desktop,
                          placement: timer.placement,
                          isHidden: timer.isHidden) { x, y in
            client.send(.moveWidget(timer.id, x: x, y: y))
        }
    }

    // MARK: 보조 동작

    private var secondaryActions: some View {
        HStack(spacing: 8) {
            actionButton("초기화", systemImage: "arrow.counterclockwise") {
                client.send(.reset(timer.id))
            }
            actionButton(timer.isHidden ? "표시" : "감추기",
                         systemImage: timer.isHidden ? "eye" : "eye.slash") {
                client.send(.toggleHidden(timer.id))
            }
            actionButton("정렬", systemImage: "rectangle.righthalf.inset.filled") {
                client.send(.align(timer.id))
            }
            actionButton("삭제", systemImage: "trash", role: .destructive) {
                client.send(.remove(timer.id))
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String,
                              role: ButtonRole? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.callout)
                Text(title)
                    .font(.caption2)
                    // 네 개가 한 줄에 들어가므로 줄바꿈을 막고 필요하면 살짝 줄인다.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
    }

    private func format(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Widget Position Pad

/// Mac 의 **화면 배치 전체**를 손바닥만 하게 옮겨 그린 판.
/// 안의 사각형을 끌면 Mac 의 타이머 창이 따라 움직이고, 화면이 여러 대면 그 사이를 넘어간다.
///
/// 방향 버튼으로 조금씩 미는 방식도 생각했지만, 발표 중에는 "저 슬라이드를 가리니까
/// 왼쪽 아래로" 나 "빔프로젝터 쪽으로" 같은 판단을 한 번에 끝내야 한다.
/// 배치를 축소해 보여주고 찍게 하면 어디로 가는지 **미리 보이고**, 한 번의 드래그로 끝난다.
///
/// 좌표 규약은 `RemotePlacement` 와 동일 — 창 **중심**의 정규화 위치, y 는 위에서 아래로,
/// 기준은 화면 한 대가 아니라 데스크탑 전체다.
struct WidgetPositionPad: View {
    let desktop: RemoteDesktop?
    let placement: RemotePlacement?
    let isHidden: Bool
    let onMove: (Double, Double) -> Void

    /// 드래그하는 동안에는 손가락을 따라가는 이 값이 판을 그린다.
    /// Mac 이 보내오는 위치만 믿고 그리면 왕복 시간만큼 사각형이 뒤늦게 따라와 끈적하게 느껴진다.
    @State private var pending: CGPoint?
    @State private var pendingSince = Date.distantPast
    @State private var isDragging = false
    @State private var lastSent = Date.distantPast

    /// 드래그 중 매 프레임 보내면 초당 60개가 나간다. 창 하나 옮기는 데 그만큼 필요하지 않고,
    /// 세션이 밀리면 오히려 늦게 도착한다. 20Hz 면 눈으로는 이어져 보인다.
    private static let sendInterval: TimeInterval = 1.0 / 20.0

    /// 화면 배치를 모를 때 그릴 기본값 — 노트북 한 대 모양.
    private var screens: [RemoteScreen] {
        let known = desktop?.screens ?? []
        guard known.isEmpty else { return known }
        return [RemoteScreen(id: 0, x: 0, y: 0, width: 1, height: 1, isMain: true)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("위치")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geo in
                pad(in: geo.size)
            }
            // 실제 배치 비율 그대로 — 판의 구석이 데스크탑의 구석과 같은 자리를 뜻해야 한다.
            .aspectRatio(CGFloat(desktop?.aspect ?? 16.0 / 10.0), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 150)
        }
        .onChange(of: placementPoint) { _, incoming in
            guard !isDragging, let pending, let incoming else { return }
            let matched = abs(incoming.x - pending.x) < 0.02 && abs(incoming.y - pending.y) < 0.02
            // 어긋난 채로 계속 붙들고 있으면 판이 영영 틀린 자리를 그린다.
            // Mac 이 다르게 판단했다면(창이 화면보다 커서 더 세게 잘렸다든지) 잠깐 뒤 Mac 을 따른다.
            if matched || Date().timeIntervalSince(pendingSince) > 0.6 { self.pending = nil }
        }
    }

    /// 화면이 여러 대일 때는 지금 어느 화면에 있는지가 위치보다 먼저 궁금하다.
    private var hint: String {
        guard placement != nil else { return "위젯 창 없음" }
        let all = desktop?.screens ?? []
        guard all.count > 1, let id = placement?.screenID else { return "끌어서 옮기기" }
        return "화면 \(id + 1)/\(all.count) · 끌어서 옮기기"
    }

    // MARK: 판

    private func pad(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // 화면 사이의 틈은 배경 없이 비워 둔다 — 배치가 그대로 보여야
            // 어느 쪽이 빔프로젝터인지 한눈에 알아본다.
            Color.clear

            ForEach(screens) { screen in
                screenRect(screen, in: size)
            }

            if let placement {
                widget(placement, in: size)
            }
        }
        // 사각형 위가 아니라 판 아무 데나 찍어도 그 자리로 간다 — 정확히 사각형을 짚을 필요가 없다.
        .contentShape(Rectangle())
        .gesture(drag(in: size))
        .opacity(placement == nil ? 0.5 : 1)
        .allowsHitTesting(placement != nil)
    }

    private func screenRect(_ screen: RemoteScreen, in size: CGSize) -> some View {
        let rect = CGRect(x: CGFloat(screen.x) * size.width,
                          y: CGFloat(screen.y) * size.height,
                          width: CGFloat(screen.width) * size.width,
                          height: CGFloat(screen.height) * size.height)
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                )
            // 메뉴 막대가 있는 화면에만 얇은 띠를 그린다.
            // 위아래 구분이자, 어느 쪽이 주 화면인지 알려주는 표시이기도 하다.
            if screen.isMain {
                Rectangle()
                    .fill(Color(.separator).opacity(0.6))
                    .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    private func widget(_ placement: RemotePlacement, in size: CGSize) -> some View {
        let center = clamp(pending ?? CGPoint(x: placement.x, y: placement.y), placement)
        // 큰 화면을 여러 대 이어 붙이면 창 비율이 아주 작아진다. 손가락으로 짚을 수는 있어야 해서
        // 그릴 때만 최소 크기를 준다 — 자르기 계산에는 실제 비율을 그대로 쓴다(Mac 과 같은 값).
        let w = max(20, CGFloat(placement.widthRatio) * size.width)
        let h = max(16, CGFloat(placement.heightRatio) * size.height)

        return RoundedRectangle(cornerRadius: 4)
            // 감춰둔 위젯은 옅게 + 점선 — 지금 화면에 안 보이는 창을 옮기고 있다는 걸 알려준다.
            .fill(Color.accentColor.opacity(isHidden ? 0.18 : 0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor,
                                  style: StrokeStyle(lineWidth: 1.5, dash: isHidden ? [3, 2] : []))
            )
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 4, y: 2)
            .scaleEffect(isDragging ? 1.08 : 1)
            .animation(.spring(duration: 0.2), value: isDragging)
            // 드래그 중에는 애니메이션을 걸지 않는다 — 손가락보다 늦게 따라오면 끈적하게 느껴진다.
            .animation(isDragging ? nil : .easeOut(duration: 0.2), value: center)
            .position(x: center.x * size.width, y: center.y * size.height)
    }

    // MARK: 제스처

    private func drag(in size: CGSize) -> some Gesture {
        // minimumDistance 0 — 톡 찍기만 해도 그 자리로 보낸다. 끌어서 옮기는 것과 같은 경로.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let point = normalized(value.location, in: size)
                pending = point
                pendingSince = Date()
                let now = Date()
                guard now.timeIntervalSince(lastSent) >= Self.sendInterval else { return }
                lastSent = now
                onMove(Double(point.x), Double(point.y))
            }
            .onEnded { value in
                isDragging = false
                let point = normalized(value.location, in: size)
                pending = point
                pendingSince = Date()
                // 마지막 자리는 스로틀과 무관하게 반드시 보낸다 —
                // 여기서 걸러버리면 손을 뗀 위치와 창의 위치가 영영 어긋난다.
                lastSent = Date()
                onMove(Double(point.x), Double(point.y))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    // MARK: 좌표

    private var placementPoint: CGPoint? {
        placement.map { CGPoint(x: $0.x, y: $0.y) }
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: min(1, max(0, location.x / size.width)),
                       y: min(1, max(0, location.y / size.height)))
    }

    /// 창이 화면 밖으로 반쯤 걸치지 않게, **가리킨 지점이 속한 화면 안으로** 자른다.
    /// Mac 쪽(`NoteManager.moveWidget`)이 하는 것과 같은 계산이라 손을 뗀 자리와
    /// 창이 멈추는 자리가 어긋나지 않는다. 데스크탑 전체로 자르면 화면 사이 빈 구석에
    /// 창을 놓게 되어 아무 화면에도 안 보이게 된다.
    private func clamp(_ point: CGPoint, _ placement: RemotePlacement) -> CGPoint {
        guard let screen = screen(nearest: point) else { return point }
        let halfW = CGFloat(placement.widthRatio) / 2
        let halfH = CGFloat(placement.heightRatio) / 2
        let minX = CGFloat(screen.x) + halfW
        let maxX = CGFloat(screen.x + screen.width) - halfW
        let minY = CGFloat(screen.y) + halfH
        let maxY = CGFloat(screen.y + screen.height) - halfH
        // 창이 화면보다 크면 min 이 max 를 넘어선다. 그때는 왼쪽 위에 붙인다 (Mac 과 동일).
        return CGPoint(x: min(max(point.x, minX), max(minX, maxX)),
                       y: min(max(point.y, minY), max(minY, maxY)))
    }

    /// 그 점을 품은 화면. 배치에 따라 어느 화면에도 속하지 않는 틈이 생기므로,
    /// 없으면 가장 가까운 화면을 고른다 (Mac 의 `ScreenMap.screen(nearest:)` 와 같은 규칙).
    private func screen(nearest point: CGPoint) -> RemoteScreen? {
        let all = screens
        if let hit = all.first(where: { rect(of: $0).contains(point) }) { return hit }
        return all.min { distance(point, rect(of: $0)) < distance(point, rect(of: $1)) }
    }

    private func rect(of screen: RemoteScreen) -> CGRect {
        CGRect(x: screen.x, y: screen.y, width: screen.width, height: screen.height)
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        // 정규화 좌표는 가로·세로를 각각 데스크탑 폭·높이로 나눈 값이라 눈금이 서로 다르다.
        // 가로에 비율을 곱해 실제 거리 비로 되돌린 뒤 비교해야 Mac(`ScreenMap.screen(nearest:)`)과
        // **같은 화면**을 고른다. 안 맞추면 화면 사이 틈에 놓았을 때 판과 창이 다른 화면을 가리킨다.
        let aspect = CGFloat(desktop?.aspect ?? 1)
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX) * aspect
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy      // 비교만 하므로 제곱근은 생략
    }
}
