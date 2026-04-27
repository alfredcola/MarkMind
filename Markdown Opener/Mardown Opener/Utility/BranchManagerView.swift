import SwiftUI

struct BranchManagerView: View {
    @EnvironmentObject var convo: ConversationStore
    let docURL: URL
    @Binding var selectedBranchId: UUID?
    @State private var showBranchList = false
    @State private var branchLabels: [UUID: String] = [:]

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { showBranchList.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.branch")
                        .font(.system(size: 14))
                    if let currentBranch = selectedBranchId {
                        Text(branchLabels[currentBranch] ?? "Branch")
                            .font(.caption)
                    } else {
                        Text("Main")
                            .font(.caption)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
            .foregroundColor(.primary)

            Spacer()

            if selectedBranchId != nil {
                Menu {
                    Button(action: mergeCurrentBranch) {
                        Label("Merge to Main", systemImage: "arrow.triangle.merge")
                    }

                    Button(role: .destructive, action: deleteCurrentBranch) {
                        Label("Delete Branch", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showBranchList) {
            BranchListSheet(
                docURL: docURL,
                selectedBranchId: $selectedBranchId,
                branchLabels: $branchLabels
            )
        }
        .onAppear {
            loadBranchLabels()
        }
    }

    private func loadBranchLabels() {
        let messages = convo.messages(for: docURL)
        var labels: [UUID: String] = [:]
        for msg in messages {
            if let branchId = msg.branchId, let label = msg.branchLabel {
                labels[branchId] = label
            }
        }
        branchLabels = labels
    }

    private func mergeCurrentBranch() {
        guard let branchId = selectedBranchId else { return }
        convo.autoMergeBranch(branchId, in: docURL)
        selectedBranchId = nil
        loadBranchLabels()
    }

    private func deleteCurrentBranch() {
        guard let branchId = selectedBranchId else { return }
        convo.deleteBranch(branchId, in: docURL)
        selectedBranchId = nil
        loadBranchLabels()
    }
}

struct BranchListSheet: View {
    let docURL: URL
    @Binding var selectedBranchId: UUID?
    @Binding var branchLabels: [UUID: String]
    @EnvironmentObject var convo: ConversationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button(action: {
                    selectedBranchId = nil
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "trunk")
                            .foregroundColor(.purple)
                        Text("Main Conversation")
                        Spacer()
                        if selectedBranchId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .foregroundColor(.primary)

                ForEach(availableBranches, id: \.id) { branch in
                    Button(action: {
                        selectedBranchId = branch.id
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "arrow.branch")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text(branch.label)
                                    .font(.subheadline)
                                Text("\(branch.messageCount) messages")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedBranchId == branch.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Merge All") {
                        convo.mergeAllBranches(in: docURL)
                        dismiss()
                    }
                    .disabled(availableBranches.isEmpty)
                }
            }
        }
    }

    private var availableBranches: [(id: UUID, label: String, messageCount: Int)] {
        let messages = convo.messages(for: docURL)
        var branchInfo: [UUID: (label: String, count: Int)] = [:]

        for msg in messages {
            if let branchId = msg.branchId, let label = msg.branchLabel {
                if var existing = branchInfo[branchId] {
                    existing.count += 1
                    branchInfo[branchId] = existing
                } else {
                    branchInfo[branchId] = (label, 1)
                }
            }
        }

        return branchInfo.map { (id: $0.key, label: $0.value.label, messageCount: $0.value.count) }
            .sorted { $0.label < $1.label }
    }
}