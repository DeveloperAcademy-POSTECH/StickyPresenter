//
//  Widget.swift
//  Widget
//
//  Created by Leeo on 7/26/26.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct TimerWidgetEntry: TimelineEntry {
    let date: Date
    /// 앱이 App Group에 기록한 타이머 상태. 타이머가 하나도 없으면 nil.
    let snapshot: TimerSnapshot?
}

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> TimerWidgetEntry {
        TimerWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerWidgetEntry) -> Void) {
        // 위젯 갤러리 미리보기에는 실제 상태가 없을 수 있으므로 샘플로 대체한다.
        let snapshot = SharedTimerStore.load() ?? (context.isPreview ? .preview : nil)
        completion(TimerWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedTimerStore.load()
        let entry = TimerWidgetEntry(date: now, snapshot: snapshot)

        // 남은 시간과 진행률은 뷰가 endDate를 받아 스스로 갱신하므로 주기적 타임라인이 필요 없다.
        // 실행 중일 때만 종료 시각에 한 번 깨어나 "완료" 표시로 전환하고,
        // 그 밖의 상태 변화는 앱이 reloadAllTimelines()로 알린다.
        let policy: TimelineReloadPolicy
        if let end = snapshot?.endDate, end > now {
            policy = .after(end)
        } else {
            policy = .never
        }

        completion(Timeline(entries: [entry], policy: policy))
    }
}

// MARK: - View

struct StickyPresenterWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    /// 앱의 완료 표시와 같은 빨강.
    private static let finishedColor = Color(red: 1, green: 0.22, blue: 0.37)

    var body: some View {
        if let snapshot = entry.snapshot {
            timerBody(snapshot)
        } else {
            emptyBody
        }
    }

    // MARK: 타이머가 있을 때

    private func timerBody(_ snapshot: TimerSnapshot) -> some View {
        let finished = snapshot.isFinished(at: entry.date)

        return VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            header(snapshot, finished: finished)
            countdown(snapshot, finished: finished)
            progressBar(snapshot, finished: finished)

            if family != .systemSmall {
                Text(detailText(snapshot, finished: finished))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func header(_ snapshot: TimerSnapshot, finished: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon(snapshot, finished: finished))
            Text(snapshot.name.isEmpty ? "타이머" : snapshot.name)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(finished ? Self.finishedColor : .secondary)
    }

    @ViewBuilder
    private func countdown(_ snapshot: TimerSnapshot, finished: Bool) -> some View {
        let font = Font.system(
            size: family == .systemSmall ? 34 : 44,
            weight: .semibold,
            design: .rounded
        )

        if finished {
            Text(TimerSnapshot.formatted(0))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(Self.finishedColor)
        } else if snapshot.isRunning, let end = snapshot.endDate {
            // .timer 스타일은 타임라인을 다시 만들지 않고도 초 단위로 스스로 줄어든다.
            Text(end, style: .timer)
                .font(font)
                .monospacedDigit()
        } else {
            Text(TimerSnapshot.formatted(snapshot.remaining(at: entry.date)))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func progressBar(_ snapshot: TimerSnapshot, finished: Bool) -> some View {
        if finished {
            ProgressView(value: 1)
                .tint(Self.finishedColor)
        } else if snapshot.isRunning,
                  let end = snapshot.endDate,
                  snapshot.targetSeconds > 0 {
            // 구간의 시작을 (종료 - 전체 시간)으로 잡으면 막대가 곧 경과 시간 비율이 된다.
            // 카운트다운 텍스트와 마찬가지로 위젯이 스스로 채워 나간다.
            ProgressView(
                timerInterval: end.addingTimeInterval(-snapshot.targetSeconds)...end,
                countsDown: false
            )
            .labelsHidden()
            .tint(.accentColor)
        } else {
            ProgressView(value: snapshot.progress(at: entry.date))
                .tint(.accentColor)
        }
    }

    // MARK: 타이머가 없을 때

    private var emptyBody: some View {
        VStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 24))
            Text("실행 중인 타이머 없음")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 표시 문구

    private func statusIcon(_ snapshot: TimerSnapshot, finished: Bool) -> String {
        if finished { return "bell.fill" }
        return snapshot.isRunning ? "timer" : "pause.circle"
    }

    private func detailText(_ snapshot: TimerSnapshot, finished: Bool) -> String {
        let total = "총 \(TimerSnapshot.formatted(snapshot.targetSeconds))"
        if finished { return "\(total) · 완료" }
        return snapshot.isRunning ? "\(total) · 진행 중" : "\(total) · 일시정지"
    }
}

// MARK: - Widget

struct StickyPresenterWidget: Widget {
    let kind: String = "StickyPresenterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            StickyPresenterWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("발표 타이머")
        .description("진행 중인 발표 타이머의 남은 시간을 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
