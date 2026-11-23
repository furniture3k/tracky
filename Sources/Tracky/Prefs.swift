import Foundation

@MainActor
final class Prefs: ObservableObject {
    enum BarMode: Int, CaseIterable, Identifiable {
        case session, today, icon
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .session: "Current session"
            case .today: "Today's total"
            case .icon: "Icon only"
            }
        }
    }

    @Published var barMode: BarMode {
        didSet { UserDefaults.standard.set(barMode.rawValue, forKey: "barMode"); onChange?() }
    }
    /// Weekly goal in hours; 0 = no goal.
    @Published var weeklyGoal: Int {
        didSet { UserDefaults.standard.set(weeklyGoal, forKey: "weeklyGoal"); onChange?() }
    }

    var onChange: (() -> Void)?

    init() {
        let d = UserDefaults.standard
        barMode = BarMode(rawValue: d.integer(forKey: "barMode")) ?? .session
        weeklyGoal = d.integer(forKey: "weeklyGoal")
    }
}
