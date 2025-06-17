//
//  FoundationModelsAppApp.swift
//  FoundationModelsApp
//
//  Created by Leo on 11/06/2025.
//

import SwiftUI

@main
struct FoundationModelsAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(story: .constant(Story(title: "My Story", text: AttributedString("This is a sample story."))))
        }
    }
}
