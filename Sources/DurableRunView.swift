import SwiftUI

struct DurableRunView: View {
    @StateObject private var controller: DurableRunController
    let capabilities: CapabilitiesResponse.Features?
    let session: HermesSession?
    let model: String?
    let provider: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var input = ""
    @State private var guidance = ""
    @State private var attachID = ""
    @State private var approvalConfirmation: ApprovalSelection?
    @State private var confirmStop = false
    @State private var confirmForget = false

    private struct ApprovalSelection: Identifiable {
        let requestID: String
        let choice: String
        var id: String { requestID + choice }
    }

    init(client: HermesAPIClient, scope: String, capabilities: CapabilitiesResponse.Features?, session: HermesSession?, model: String?, provider: String?) {
        _controller = StateObject(wrappedValue: DurableRunController(client: client, connectionScope: scope, supportsDurableAdmission: capabilities?.runSubmission == true && capabilities?.runsIdempotency?.supported == true && capabilities?.runsIdempotency?.durable == true, retentionSeconds: capabilities?.runsIdempotency?.retention_seconds ?? 0, supportsEventReplay: capabilities?.runEventReplay?.supported == true && capabilities?.runEventReplay?.fanout == true))
        self.capabilities = capabilities; self.session = session; self.model = model; self.provider = provider
    }

    var body: some View {
        List {
            if let failure = controller.operationFailure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let failure = controller.failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let notice = controller.streamNotice { Text(notice).foregroundStyle(.secondary) }
            Section("Run Connection") {
                if let id = controller.runID { Text(id).font(.caption.monospaced()).textSelection(.enabled) }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let last = controller.lastResponseAt {
                        Text("Hermes status received \(max(0, Int(context.date.timeIntervalSince(last))))s ago")
                    } else { Text("Waiting for Hermes status") }
                }.font(.caption)
                Text(controller.activity).font(.caption)
                if let status = controller.status {
                    LabeledContent("State", value: status.status)
                    if let sessionID = status.session_id { LabeledContent("Session", value: sessionID).font(.caption) }
                    if let error = status.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
                Text("Closing this screen leaves the server run active. Returning reconnects to the saved run ID for this server.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if controller.runID == nil || controller.status?.isTerminal == true {
                Section("Start Durable Run") {
                    Text(session.map { "Continue conversation: \($0.title ?? $0.id)" } ?? "Start a new server conversation")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Message for Hermes", text: $input, axis: .vertical).lineLimit(3...10)
                        .disabled(controller.submissionUncertain || controller.isWorking)
                    Button(controller.submissionUncertain ? "Retry Admission" : "Start Run") {
                        Task { await controller.submit(input: input, sessionID: session?.id, model: model, provider: provider) }
                    }.disabled(controller.isWorking || !controller.supportsDurableAdmission || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !controller.supportsDurableAdmission { Text("This gateway must advertise durable run submission and durable idempotency to start work here.").foregroundStyle(.orange) }
                }
            }
            if let approval = controller.status?.approval, controller.status?.status == "waiting_for_approval" {
                Section("Hermes Requests Approval") {
                    if let description = approval.description { Text(description) }
                    if let command = approval.command { Text(command).font(.body.monospaced()).textSelection(.enabled) }
                    if approval.offeredChoices.isEmpty {
                        Text("Hermes omitted an exact request ID or supported choices. Refresh status or resolve this request on the server.").foregroundStyle(.orange)
                    }
                    ForEach(approval.offeredChoices, id: \.self) { choice in
                        Button(choiceLabel(choice), role: choice == "deny" ? .destructive : nil) {
                            guard let requestID = approval.request_id else { return }
                            if choice == "session" || choice == "always" {
                                approvalConfirmation = ApprovalSelection(requestID: requestID, choice: choice)
                            } else { Task { await controller.decide(requestID: requestID, choice: choice) } }
                        }.disabled(controller.isWorking || !controller.hasFreshStatus || capabilities?.runApprovalResponse != true)
                    }
                }
            }
            if controller.status?.status == "running" {
                Section("Guide This Run") {
                    TextField("Additional guidance", text: $guidance, axis: .vertical).lineLimit(2...6)
                    Button("Send Guidance") {
                        let sent = guidance
                        Task { if await controller.steer(sent), guidance == sent { guidance = "" } }
                    }.disabled(controller.isWorking || !controller.hasFreshStatus || capabilities?.runSteer != true || guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let status = controller.status, !status.isTerminal {
                Section {
                    Button("Stop Server Run", role: .destructive) { confirmStop = true }
                        .disabled(controller.isWorking || !controller.hasFreshStatus || capabilities?.runStop != true || status.status == "stopping")
                }
            }
            if let pending = controller.status?.pending_steer, !pending.isEmpty {
                Section("Guidance Not Delivered") {
                    Text(pending).textSelection(.enabled)
                    Text("Hermes finished before consuming this guidance. It has not been sent again automatically.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let output = controller.status?.output, !output.isEmpty {
                Section("Server Result") { Text(output).textSelection(.enabled) }
            } else if !controller.liveText.isEmpty {
                Section(controller.liveOutputIncomplete ? "Live Response (Partial)" : "Live Response") {
                    Text(controller.liveText).textSelection(.enabled)
                    if controller.liveOutputIncomplete { Text("Some live output could not be retained. Hermes's final saved result will replace this partial view.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if controller.runID != nil {
                Section { Button("Stop Tracking This Run") { confirmForget = true }.disabled(controller.isWorking) }
            }
            Section("Attach to a Run") {
                TextField("run_ identifier from this gateway", text: $attachID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Attach") { Task { await controller.attach(attachID.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                    .disabled(controller.isWorking || attachID.isEmpty || controller.submissionUncertain)
            }
        }
        .navigationTitle("Run Controls")
        .onAppear { if let pending = controller.pendingInput { input = pending } }
        .task(id: "\(scenePhase)-\(controller.runID ?? "")") {
            if scenePhase == .active { await controller.monitor() }
        }
        .confirmationDialog("Forget the local run bookmark?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Stop Tracking") { controller.forgetBookmark() }
        } message: { Text("This removes only the saved run ID on this device. Hermes may still be working; it does not stop or cancel the server run. Copy the run ID first if you need to attach again.") }
        .confirmationDialog("Stop this server run?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Request Stop", role: .destructive) { Task { await controller.stop() } }
        } message: { Text("Hermes may take time to interrupt the current tool. Stopping is complete only when status becomes terminal.") }
        .confirmationDialog(approvalConfirmation?.choice == "always" ? "Allow future matching operations?" : "Allow matching operations for this session?", isPresented: Binding(get: { approvalConfirmation != nil }, set: { if !$0 { approvalConfirmation = nil } }), titleVisibility: .visible) {
            if let selection = approvalConfirmation {
                Button(choiceLabel(selection.choice)) { Task { await controller.decide(requestID: selection.requestID, choice: selection.choice) } }
            }
        } message: { Text("This permission is broader than approving this operation once. Hermes applies the scope to the displayed approval pattern.") }
        .interactiveDismissDisabled(controller.isWorking)
    }

    private func choiceLabel(_ choice: String) -> String {
        switch choice {
        case "once": "Allow Once"
        case "session": "Allow for Session"
        case "always": "Always Allow Matching Operations"
        default: "Deny"
        }
    }
}
