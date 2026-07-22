import SwiftUI
import LeeoKit

struct StickyPresenterSupportView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LeeoSupportSection<StickyPresenterSpec>()
                } header: {
                    Text("지원")
                }
            }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
