import SwiftUI

public struct WebSceneView: View {
    let bridge: WebSceneBridge
    let config: WebSceneConfig

    public init(bridge: WebSceneBridge, config: WebSceneConfig) {
        self.bridge = bridge
        self.config = config
    }

    public var body: some View {
        WebSceneHost(bridge: bridge, config: config)
            .ignoresSafeArea()
    }
}
