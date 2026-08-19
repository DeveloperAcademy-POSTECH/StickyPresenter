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
                    // 그 뒤 복귀했을 때 죽은 세션으로 계속 시도하게 된다. 깨끗이 끊고 다시 찾는다.
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
            Group {
                if client.timers.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(client.timers) { timer in
                            TimerRemoteRow(timer: timer)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        }
                        presetSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Timer Remote")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { connectionBadge }
            }
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(client.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var isConnected: Bool {
        if case .connected = client.status { return true }
        return false
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isConnected ? "timer" : "wifi.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isConnected ? "실행 중인 타이머가 없습니다" : client.status.label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if isConnected {
                Text("아래에서 프리셋을 눌러 시작하세요")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                presetRow
                    .padding(.top, 4)
            } else {
                Text("Mac과 같은 Wi-Fi에 연결되어 있어야 합니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
    }

    private var presetSection: some View {
        Section("새 타이머") { presetRow }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach([("3m", 180.0), ("5m", 300.0), ("10m", 600.0), ("15m", 900.0)], id: \.0) { label, secs in
                Button(label) { client.send(.addPreset(seconds: secs, name: label)) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(!isConnected)
    }
}

// MARK: - Row

struct TimerRemoteRow: View {
    @EnvironmentObject private var client: RemoteClient
    let timer: RemoteTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            timeDisplay
            transportControls
            widgetControls
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack {
            if timer.isPomodoro, let phase = timer.phaseTitle {
                Text("\(phase) · #\(timer.cycleNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
            } else {
                Text(timer.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if timer.isFinished {
                Text("완료")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.red))
            }
        }
    }

    private var timeDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(format(timer.remaining))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.linear(duration: 0.3), value: timer.remaining)
            Spacer()
            ProgressView(value: timer.progress)
                .frame(width: 80)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            control("−30s") { client.send(.subtractSeconds(timer.id)) }
            Button {
                client.send(.toggleRun(timer.id))
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            control("+30s") { client.send(.addSeconds(timer.id)) }
            control("초기화") { client.send(.reset(timer.id)) }
        }
    }

    private var widgetControls: some View {
        HStack(spacing: 8) {
            // 크기 프리셋 — Mac 쪽 S/M/L 버튼과 같은 동작
            ForEach(["S", "M", "L"], id: \.self) { size in
                Button(size) { client.send(.setSize(timer.id, size)) }
                    .buttonStyle(.bordered)
                    .tint(timer.size == size ? .accentColor : .gray)
                    .frame(maxWidth: .infinity)
            }
            control(timer.isHidden ? "표시" : "감추기") { client.send(.toggleHidden(timer.id)) }
            control("정렬") { client.send(.align(timer.id)) }
            Button(role: .destructive) {
                client.send(.remove(timer.id))
            } label: {
                Image(systemName: "xmark").frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
        }
    }

    private func control(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
    }

    private func format(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }
}
