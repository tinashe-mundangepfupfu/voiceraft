import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let delegate = MainActor.assumeIsolated { VoiceRaftAppDelegate() }
MainActor.assumeIsolated {
    application.delegate = delegate
}

application.run()
