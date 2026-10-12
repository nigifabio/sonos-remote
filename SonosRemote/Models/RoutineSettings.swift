import Foundation

/// User-tunable parameters for the one-tap routines, stored in UserDefaults
/// (the Settings window edits the same keys through `@AppStorage`).
struct RoutineSettings: Equatable {
    static let goodnightMinutesKey = "routineGoodnightMinutes"
    static let goodnightMaxVolumeKey = "routineGoodnightMaxVolume"
    static let movieNightVolumeKey = "routineMovieNightVolume"
    static let movieNightPauseOthersKey = "routineMovieNightPauseOthers"

    var goodnightMinutes = 30
    /// Rooms louder than this are lowered to it. Nil leaves volumes alone.
    var goodnightMaxVolume: Int?
    /// Volume the TV room is set to. Nil leaves it alone.
    var movieNightVolume: Int?
    var movieNightPauseOthers = true

    init() {}

    /// In storage, 0 means "don't change the volume" for both volume keys.
    init(defaults: UserDefaults) {
        let minutes = defaults.integer(forKey: Self.goodnightMinutesKey)
        goodnightMinutes = minutes > 0 ? minutes : 30
        let cap = defaults.integer(forKey: Self.goodnightMaxVolumeKey)
        goodnightMaxVolume = cap > 0 ? cap : nil
        let movieVolume = defaults.integer(forKey: Self.movieNightVolumeKey)
        movieNightVolume = movieVolume > 0 ? movieVolume : nil
        movieNightPauseOthers = defaults.object(forKey: Self.movieNightPauseOthersKey) as? Bool ?? true
    }
}
