import SwiftUI

struct AddAccountView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var switcher: AccountSwitcher
    @State private var accountName = ""
    @State private var step: AddAccountStep = .enterName
    @FocusState private var isTextFieldFocused: Bool

    enum AddAccountStep {
        case enterName
        case waitingForLogin
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Add New Account")
                    .font(.headline)
            }

            Divider()

            switch step {
            case .enterName:
                enterNameView
            case .waitingForLogin:
                waitingForLoginView
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear {
            // Delay focus to allow the sheet to fully present
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: switcher.isAddingAccount) { isAdding in
            if isAdding {
                step = .waitingForLogin
            } else {
                if switcher.errorMessage == nil {
                    isPresented = false
                } else {
                    step = .enterName
                    // Re-focus when returning to enter name
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
                }
            }
        }
    }

    private var enterNameView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Account Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g., Work, Personal, Client Project", text: $accountName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)

                Text("This name helps you identify the account in the menu.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What happens next:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    stepRow(number: 1, text: "Terminal will open with claude login")
                    stepRow(number: 2, text: "Complete the login in your browser")
                    stepRow(number: 3, text: "Return here once logged in")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Continue") {
                    Task {
                        await switcher.addAccount(name: accountName.isEmpty ? "New Account" : accountName)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var waitingForLoginView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Waiting for login...")
                    .font(.headline)

                Text("Complete the login in Terminal, then return here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "terminal.fill")
                    Text("Terminal should be open with claude login")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "globe")
                    Text("Complete login in your browser")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("This window will update automatically")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Button("Cancel") {
                switcher.cancelAddAccount()
                isPresented = false
            }
            .foregroundColor(.secondary)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}
