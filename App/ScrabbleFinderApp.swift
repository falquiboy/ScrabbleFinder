//
//  ScrabbleFinderApp.swift
//  ScrabbleFinder
//
//  Created by Isaac Falconer on 2025.05.17.
//

import SwiftUI

@main
struct ScrabbleFinderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    // Force portrait orientation app-wide
                    AppDelegate.orientationLock = UIInterfaceOrientationMask.portrait
                }
        }
    }
}

// MARK: - AppDelegate for Orientation Control
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
