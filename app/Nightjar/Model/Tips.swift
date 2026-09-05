import Foundation

/// Short, practical, and careful. None of this is medical advice, and the
/// Rest screen says so once. Every line is a thing a person can do tonight.
struct Tip: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case fallingAsleep
        case stayingAsleep
        case room
        case daytime
        case mind

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fallingAsleep: return "Falling asleep"
            case .stayingAsleep: return "Staying asleep"
            case .room: return "The room"
            case .daytime: return "The day before"
            case .mind: return "A busy mind"
            }
        }
    }

    let id: String
    let group: Group
    let title: String
    let body: String
    /// One line on why it works.
    let why: String
}

enum Tips {
    /// Deterministic per calendar day, so it does not change under you.
    static func tonight(_ date: Date = Date()) -> Tip {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return all[(day * 7) % all.count]
    }

    static func grouped() -> [(group: Tip.Group, tips: [Tip])] {
        Tip.Group.allCases.map { group in
            (group, all.filter { $0.group == group })
        }
    }

    static let all: [Tip] = [
        // Falling asleep
        Tip(id: "same-time", group: .fallingAsleep,
            title: "Same time, every morning",
            body: "Pick a wake time and keep it, weekends included. Bedtime will follow on its own.",
            why: "The body clock is set by when you get up, not when you lie down."),
        Tip(id: "twenty-minutes", group: .fallingAsleep,
            title: "Twenty minutes, then get up",
            body: "If you are wide awake, leave the bed. Sit somewhere dim and dull until you feel heavy, then come back.",
            why: "Lying awake teaches the brain that bed is where you lie awake."),
        Tip(id: "sleepy-not-tired", group: .fallingAsleep,
            title: "Go to bed sleepy, not tired",
            body: "Tired is the body. Sleepy is the eyes closing on their own. Wait for the second one.",
            why: "Turning in before sleep pressure builds is the most common reason people stare at the ceiling."),
        Tip(id: "long-exhale", group: .fallingAsleep,
            title: "Make the exhale longer",
            body: "In through the nose for four, out through the mouth for six or eight. A few minutes is enough.",
            why: "A long exhale slows the heart through the vagus nerve. It is the fastest lever you have."),
        Tip(id: "dim-hour", group: .fallingAsleep,
            title: "Dim the house an hour out",
            body: "Overheads off, lamps on. Screens down to their lowest brightness, or away.",
            why: "Bright light in the evening pushes melatonin later. Dim light lets it start."),
        Tip(id: "warm-shower", group: .fallingAsleep,
            title: "A warm shower, then a cool room",
            body: "Ninety minutes before bed, ten minutes warm. Then let yourself cool down.",
            why: "Core temperature has to drop to fall asleep. Warming the skin first speeds the drop."),
        Tip(id: "clock-away", group: .fallingAsleep,
            title: "Turn the clock away",
            body: "Face it to the wall, or put the phone face down across the room.",
            why: "Checking the time starts the arithmetic, and arithmetic is not sleep."),

        // Staying asleep
        Tip(id: "dont-check", group: .stayingAsleep,
            title: "Wake at 3? Do not check the time",
            body: "Everyone surfaces a few times a night. Roll over. It is only a problem if you make it one.",
            why: "Brief waking is normal sleep architecture. Attention is what turns it into insomnia."),
        Tip(id: "steady-sound", group: .stayingAsleep,
            title: "Keep the sound on all night",
            body: "Use Fade to quiet instead of Stop. A steady bed covers the door, the pipes, the street.",
            why: "It is not the noise that wakes you, it is the change. Steady sound masks the change."),
        Tip(id: "water-earlier", group: .stayingAsleep,
            title: "Front-load your water",
            body: "Drink through the day and taper after dinner.",
            why: "Fewer trips up. Each one is a chance to fully wake."),
        Tip(id: "alcohol", group: .stayingAsleep,
            title: "Wine helps you fall asleep and wrecks the second half",
            body: "If you drink, finish three hours before bed.",
            why: "Alcohol is sedating early and fragmenting later, once it wears off."),
        Tip(id: "cool-room", group: .stayingAsleep,
            title: "Cooler than feels right",
            body: "Around 18 °C, 65 °F. A cool room and a warm cover.",
            why: "Warm rooms cause more waking in the early hours than almost anything else."),
        Tip(id: "back-to-sleep", group: .stayingAsleep,
            title: "Falling back asleep is a skill",
            body: "Do not try. Follow the sound. Count slow breaths to ten and start over.",
            why: "Effort is arousal. The trick is giving the mind something dull to hold."),

        // The room
        Tip(id: "dark", group: .room,
            title: "Darker than you think",
            body: "Standby lights, the gap in the curtain, the hallway. Tape, blackout, a mask.",
            why: "Even dim light through closed eyelids lightens sleep."),
        Tip(id: "bed-for-sleep", group: .room,
            title: "The bed is for sleep",
            body: "Work, scrolling, and worrying happen somewhere else. Even the sofa is better.",
            why: "The brain learns places. Keep the association clean."),
        Tip(id: "phone-outside", group: .room,
            title: "Charge the phone outside the room",
            body: "A cheap alarm clock does the one job the phone was doing.",
            why: "Removes the check, the glow, and the 1 a.m. rabbit hole in one move."),
        Tip(id: "fan", group: .room,
            title: "A fan does two jobs",
            body: "Air moving over skin cools you, and the sound covers the house.",
            why: "Most people who sleep well have some kind of steady sound and moving air."),
        Tip(id: "partner", group: .room,
            title: "One earbud, low",
            body: "If you share a bed, a single earbud on the outside ear keeps the sound yours.",
            why: "What settles you may be noise to them. The mix does not need to be loud."),

        // The day before
        Tip(id: "caffeine", group: .daytime,
            title: "Last coffee before two",
            body: "Caffeine's half-life is five to six hours. An afternoon cup is still a quarter there at midnight.",
            why: "It blocks the signal that makes you sleepy. You will still fall asleep, just lighter."),
        Tip(id: "morning-light", group: .daytime,
            title: "Ten minutes of sky in the morning",
            body: "Outside, within an hour of waking, no sunglasses. Overcast still counts.",
            why: "Morning light is the strongest cue the clock gets. It sets tonight's melatonin timing."),
        Tip(id: "nap", group: .daytime,
            title: "Nap short and early",
            body: "Twenty minutes, before three. Or skip it and bank the pressure.",
            why: "A long or late nap spends the sleepiness you need at night."),
        Tip(id: "move", group: .daytime,
            title: "Move, earlier",
            body: "A walk, a workout, anything. Finish hard exercise a couple of hours before bed.",
            why: "Exercise deepens sleep. Late exercise raises core temperature at the wrong time."),
        Tip(id: "big-meal", group: .daytime,
            title: "Eat dinner earlier than you want to",
            body: "Two to three hours before bed. Lighter is better.",
            why: "Digestion keeps the body warm and busy."),
        Tip(id: "weekend", group: .daytime,
            title: "Sleep in by an hour at most",
            body: "A lie-in feels like recovery and is mostly jet lag.",
            why: "A two-hour shift on Sunday makes Monday night's bedtime feel two hours early."),

        // A busy mind
        Tip(id: "worry-list", group: .mind,
            title: "Write tomorrow down",
            body: "Before bed, a list. Everything you are holding, next to what you will do about it.",
            why: "The brain rehearses what it is afraid of forgetting. Paper lets it stop."),
        Tip(id: "not-tonight", group: .mind,
            title: "You do not have to solve it tonight",
            body: "Name the thought, tell it you will see it at nine tomorrow, and come back to the breath.",
            why: "Postponing works where suppressing does not."),
        Tip(id: "count-back", group: .mind,
            title: "Count backwards from 300 in threes",
            body: "Slowly. If you lose your place, start over. Nobody finishes.",
            why: "Dull enough to bore you, hard enough to crowd out the loop."),
        Tip(id: "body-scan", group: .mind,
            title: "Feel each part let go",
            body: "Toes, then feet, then calves. Notice the weight of each one on the mattress. Work up.",
            why: "Attention on the body pulls it away from the story."),
        Tip(id: "one-bad-night", group: .mind,
            title: "One bad night costs almost nothing",
            body: "Tomorrow will be fine. The pressure you build tonight makes tomorrow night easier.",
            why: "Fear of not sleeping is the thing most likely to keep you from sleeping."),
        Tip(id: "same-sound", group: .mind,
            title: "Same sound every night",
            body: "Pick a mix and keep it. Let it get boring.",
            why: "A familiar sound becomes a cue. The brain hears it and knows what comes next."),
    ]
}
