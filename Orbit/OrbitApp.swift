//
//  OrbitApp.swift
//  Orbit
//
//  Created by Коханенко Роман on 17.07.2026.
//

import SwiftUI

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
