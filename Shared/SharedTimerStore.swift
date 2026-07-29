import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 앱과 위젯 익스텐션이 타이머 스냅샷을 주고받는 App Group 저장소.
///
/// 두 타겟이 같은 파일을 컴파일하므로 키와 그룹 ID가 어긋날 일이 없다.
enum SharedTimerStore {

    /// macOS의 App Group 식별자는 팀 식별자 접두사가 반드시 붙어야 한다.
    /// (iOS와 달리 `group.` 으로 시작하는 형태만으로는 컨테이너가 열리지 않는다.)
    static let appGroupID = "QGAQ3AY3R3.group.com.leeo.StickyPresenter"

    /// 위젯에 노출할 대표 타이머 하나를 담는 키.
    private static let snapshotKey = "primaryTimerSnapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// 저장된 스냅샷을 읽는다. App Group이 아직 설정되지 않았거나 값이 없으면 nil.
    static func load() -> TimerSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(TimerSnapshot.self, from: data)
    }

    /// 스냅샷을 저장하고 위젯을 갱신한다. nil을 넘기면 저장된 값을 지운다.
    static func save(_ snapshot: TimerSnapshot?) {
        guard let defaults else { return }

        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        } else {
            defaults.removeObject(forKey: snapshotKey)
        }

        reloadWidgets()
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
