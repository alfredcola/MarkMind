//
//  MCStudyView.swift
//  Markdown Opener
//
//  Created by alfred chen on 10/11/2025.
//
import SwiftUI

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

struct MCStudyResult: Codable, Identifiable {
    var id = UUID()
    let documentName: String  // ← This is now the key identifier
    let date: Date
    let totalMarks: Int
    let totalAttempts: Int
    let cards: [MCcardResult]

    var scorePercentage: Double {
        totalAttempts > 0
            ? Double(totalMarks) / Double(totalAttempts * 10) * 100 : 0
    }
}

struct MCcardResult: Codable {
    let question: String
    let options: [String]
    let correctIndex: Int
    let correctIndices: [Int]?
    let questionType: MCQuestionType
    let userIndex: Int?
    let userIndices: [Int]?
    let isCorrect: Bool
    let explanation: String?
}

enum MCLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case traditionalChinese = "正體中文"

    var id: String { rawValue }

    var promptInstruction: String {
        switch self {
        case .english:
            return
                "Generate all questions, options, and explanations in clear, natural English."
        case .traditionalChinese:
            return
                "Generate all questions, options, and explanations in Traditional Chinese (正體中文)."
        }
    }
}

extension DispatchQueue {
    private static var onceTracker = Set<String>()

    static func asyncOnce(token: String, execute work: @escaping () -> Void) {
        objc_sync_enter(onceTracker)
        defer { objc_sync_exit(onceTracker) }

        if onceTracker.contains(token) { return }
        onceTracker.insert(token)
        DispatchQueue.main.async(execute: work)
    }
}
