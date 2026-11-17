//
//  TVRemoteApp.swift
//  TVRemote
//

import SwiftUI

@main
struct TVRemoteApp: App {
    @StateObject private var controller = RemoteController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
    }
}
