import SwiftUI

@main
struct XiaohaBatteryTrackerApp: App {
    @StateObject private var service = XiaohaCloudService()
    
    var body: some Scene {
        WindowGroup {
            BatteryDetailView()
                .environmentObject(service)
                .preferredColorScheme(.dark)
        }
    }
}
