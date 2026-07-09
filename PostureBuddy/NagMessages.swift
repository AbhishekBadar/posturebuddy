import Foundation

/// The pool of lines the character says when it catches you slouching.
///
/// `next()` picks at random but never returns the same line twice in a row —
/// an immediate repeat reads like a bug rather than a joke.
struct NagMessages {
    static let all: [String] = [
        "Nice hunchback. Very medieval.",
        "You're folding like a cheap lawn chair.",
        "Oh good, the shrimp posture again.",
        "Your neck called. It's resigning.",
        "Standing desk influencers hate you.",
        "That's not a spine, it's a croissant.",
        "Gravity: 1. You: 0.",
        "You look like a question mark.",
        "The chair is winning, by the way.",
        "Sit up before I tell your mother.",
        "Ah yes, the goblin crouch.",
        "Your future chiropractor thanks you.",
    ]

    private var lastIndex: Int?

    mutating func next() -> String {
        let messages = Self.all
        guard let first = messages.first else { return "Sit straight!" }
        guard messages.count > 1 else { return first }

        var index = Int.random(in: messages.indices)
        while index == lastIndex {
            index = Int.random(in: messages.indices)
        }
        lastIndex = index
        return messages[index]
    }
}
