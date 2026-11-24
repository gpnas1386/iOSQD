//
//  TVRemoteApp.swift
//  TVRemote
//

import SwiftUI

@main
struct TVRemoteApp: App {
    @StateObject private var controller = RemoteController()
    @StateObject private var layoutStore = PadLayoutStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .environmentObject(layoutStore)
        }
    }
}
