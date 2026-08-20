import SwiftUI

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
            ContentUnavailableView {
                Label("Mac을 찾는 중", systemImage: "wifi.slash")
            } description: {
                Text(client.status.label)
            } actions: {
                Text("Mac과 같은 Wi-Fi에 연결되어 있어야 합니다")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        } else if client.timers.isEmpty {
            ContentUnavailableView {
                Label("실행 중인 타이머 없음", systemImage: "timer")
            } description: {
                Text("아래에서 시간을 골라 시작하세요")
            } actions: {
                PresetRow().environmentObject(client)
                    .padding(.horizontal, 32)
            }
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

// MARK: - Presets

struct PresetRow: View {
    @EnvironmentObject private var client: RemoteClient

    /// (버튼에 보일 글자, 타이머 이름, 초).
    /// 이름은 Mac 앱의 프리셋과 **같은 표기**를 쓴다 — 여기서 "5분"으로 만들면
    /// Mac 목록과 알림 센터 위젯에 "5m"과 "5분"이 섞여 보인다.
    private static let presets: [(label: String, name: String, seconds: Double)] =
        [("3분", "3m", 180), ("5분", "5m", 300), ("10분", "10m", 600), ("15분", "15m", 900)]

    var body: some View {
        HStack(spacing: 8) {
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
