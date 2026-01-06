import SwiftUI

// This file is kept for backwards compatibility but the main views are in MenuBarView.swift

struct RenameAccountView: View {
    let account: Account
    @Binding var newName: String
    @Binding var isPresented: Bool
    @EnvironmentObject var switcher: AccountSwitcher

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Account")
                .font(.headline)

            TextField("Account Name", text: $newName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    switcher.renameAccount(account, to: newName)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.isEmpty)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
