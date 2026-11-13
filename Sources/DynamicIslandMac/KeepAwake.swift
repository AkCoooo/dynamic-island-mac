import Combine
import IOKit.pwr_mgt

/// Empêche la mise en veille de l'écran pendant la lecture, si l'option est activée.
final class KeepAwake {
    private var assertion: IOPMAssertionID = 0
    private var cancellables: Set<AnyCancellable> = []

    init(model: NotchModel) {
        model.$isPlaying.combineLatest(AppSettings.shared.$keepAwakeWhilePlaying)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] playing, enabled in self?.set(playing && enabled) }
            .store(in: &cancellables)
    }

    private func set(_ awake: Bool) {
        if awake, assertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Lecture de musique en cours" as CFString, &assertion)
        } else if !awake, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}
