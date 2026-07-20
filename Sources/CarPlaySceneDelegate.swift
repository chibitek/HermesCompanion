import CarPlay
import Combine

/// CarPlay scene: single list template with a Talk toggle and live voice state.
/// Voice Mode is the whole product here — no chat UI in the car.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    private let controller = CarPlayVoiceController.shared

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeTemplate(), animated: false, completion: nil)

        // Rebuild the list whenever voice state changes.
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.interfaceController != nil else { return }
                self.interfaceController?.setRootTemplate(self.makeTemplate(), animated: false, completion: nil)
            }
            .store(in: &cancellables)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {
        controller.stop()
        self.interfaceController = nil
        cancellables.removeAll()
    }

    private func makeTemplate() -> CPListTemplate {
        var items: [CPListItem] = []

        let talk = CPListItem(text: controller.isActive ? "Stop" : "Talk to Hermes",
                              detailText: controller.stateText)
        talk.handler = { [weak self] _, completion in
            self?.controller.toggleConversation()
            completion()
        }
        items.append(talk)

        if !controller.lastTranscription.isEmpty {
            items.append(CPListItem(text: "You", detailText: controller.lastTranscription))
        }
        if !controller.lastResponse.isEmpty {
            items.append(CPListItem(text: "Hermes",
                                    detailText: String(controller.lastResponse.prefix(200))))
        }

        let section = CPListSection(items: items)
        return CPListTemplate(title: "Hermes", sections: [section])
    }
}
