//
//  StoryModel.swift
//  FoundationModelsApp
//
//  Created by Leo on 6/16/25.
//
import Foundation
import AVFoundation

@Observable
class Story: Identifiable {
    typealias StartTime = CMTime
    
    let id: UUID
    var title: String
    var text: AttributedString
    var url: URL?
    var isDone: Bool
    
    init(title: String, text: AttributedString, url: URL? = nil, isDone: Bool = false) {
        self.title = title
        self.text = text
        self.url = url
        self.isDone = isDone
        self.id = UUID()
    }
}
