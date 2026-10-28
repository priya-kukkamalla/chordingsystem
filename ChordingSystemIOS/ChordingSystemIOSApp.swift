import SwiftUI

@main
struct ChordingSystemIOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSContentView()
                .onAppear {
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .forEach {
                            $0.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                        }
                }
        }
    }
}
