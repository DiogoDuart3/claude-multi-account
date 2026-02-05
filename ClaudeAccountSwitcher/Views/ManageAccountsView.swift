import SwiftUI
import AppKit

struct ManageAccountsView: View {
    @ObservedObject var switcher: AccountSwitcher
    @State private var editingAccountId: UUID?
    @State private var editingName: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(switcher.accounts) { account in
                    AccountManagementRow(
                        account: account,
                        isEditing: editingAccountId == account.id,
                        editingName: $editingName,
                        onStartEdit: {
                            editingAccountId = account.id
                            editingName = account.name
                        },
                        onSaveEdit: {
                            switcher.renameAccount(account, to: editingName)
                            editingAccountId = nil
                        },
                        onCancelEdit: {
                            editingAccountId = nil
                        },
                        onDelete: {
                            switcher.removeAccount(account)
                        },
                        isActive: account.isActive
                    )
                }
            }
            .listStyle(.inset)
            
            Divider()
            
            HStack {
                Text("\(switcher.accounts.count) account(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}

struct AccountManagementRow: View {
    let account: Account
    let isEditing: Bool
    @Binding var editingName: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    let isActive: Bool
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "person.circle.fill" : "person.circle")
                .font(.title2)
                .foregroundStyle(isActive ? .blue : .secondary)
            
            if isEditing {
                TextField("Account name", text: $editingName, onCommit: onSaveEdit)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: onSaveEdit) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                
                Button(action: onCancelEdit) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(account.name)
                            .fontWeight(isActive ? .semibold : .regular)
                        if isActive {
                            Text("Active")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    if let rateLimit = account.cachedRateLimit {
                        HStack(spacing: 8) {
                            if let sessionUsed = rateLimit.sessionUsed {
                                let sessionLeft = max(0, 100 - sessionUsed)
                                Text("Session: \(sessionLeft)%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let weeklyUsed = rateLimit.weeklyUsed {
                                let weeklyLeft = max(0, 100 - weeklyUsed)
                                Text("Weekly: \(weeklyLeft)%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onStartEdit) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rename account")
                
                Button {
                    if isActive {
                        showActiveAccountAlert()
                    } else {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(isActive ? Color.secondary.opacity(0.5) : Color.red)
                }
                .buttonStyle(.plain)
                .help(isActive ? "Cannot delete active account" : "Delete account")
                .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } message: {
                    Text("Are you sure you want to delete \"\(account.name)\"? This cannot be undone.")
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func showActiveAccountAlert() {
        let alert = NSAlert()
        alert.messageText = "Cannot Delete Active Account"
        alert.informativeText = "Switch to another account first before deleting this one."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

class ManageAccountsWindowController {
    static let shared = ManageAccountsWindowController()
    private var window: NSWindow?
    
    func showWindow(switcher: AccountSwitcher) {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = ManageAccountsView(switcher: switcher)
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Manage Accounts"
        newWindow.styleMask = [.titled, .closable, .resizable]
        newWindow.setContentSize(NSSize(width: 400, height: 300))
        newWindow.minSize = NSSize(width: 350, height: 200)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        
        self.window = newWindow
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
