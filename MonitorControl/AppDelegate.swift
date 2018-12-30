//
//  AppDelegate.swift
//  MonitorControl
//
//  Created by Mathew Kurian on 9/26/16.
//  Last edited by Guillaume Broder on 9/17/2017
//  Last edited by Jerome Lambourg on 30/12/2018
//  MIT Licensed.
//

import Cocoa
import Foundation
import MediaKeyTap
import MASPreferences

var app: AppDelegate! = nil
let prefs = UserDefaults.standard

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, MediaKeyTapDelegate, AudioCtrlDelegate {

  @IBOutlet weak var statusMenu: NSMenu!
  @IBOutlet weak var window: NSWindow!

  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

  var displays: [Display] = []
  var audioOutDisplay: Display?

  let step = 100/16

  var mediaKeyTap: MediaKeyTap?
  var prefsController: NSWindowController?

  static let keysNoAudio: [MediaKey] = [.brightnessUp, .brightnessDown]
  static let keysWithAudio: [MediaKey] = [.brightnessUp, .brightnessDown, .mute, .volumeUp, .volumeDown]

  var keysListenedFor: [MediaKey] = AppDelegate.keysNoAudio

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    app = self

    mediaKeyTap = MediaKeyTap.init(delegate: self, for: keysListenedFor, observeBuiltIn: false)
    let storyboard: NSStoryboard = NSStoryboard.init(name: "Main", bundle: Bundle.main)
    let views = [
      storyboard.instantiateController(withIdentifier: "MainPrefsVC"),
      storyboard.instantiateController(withIdentifier: "DisplayPrefsVC")
    ]
    prefsController = MASPreferencesWindowController(viewControllers: views, title: NSLocalizedString("Preferences", comment: "Shown in Preferences window"))

    NotificationCenter.default.addObserver(self, selector: #selector(handleShowContrastChanged), name: NSNotification.Name.init(Utils.PrefKeys.showContrast.rawValue), object: nil)

    statusItem.title = "🖥️"
    statusItem.menu = statusMenu

    setDefaultPrefs()

    Utils.acquirePrivileges()

    CGDisplayRegisterReconfigurationCallback({_, _, _ in app.updateDisplays()}, nil)
    updateDisplays()

    AudioCtrl.instance.registerDelegate(self)
    self.onDefaultAudioOutputChange(AudioCtrl.instance.defaultOutputName)
  }

  func applicationWillTerminate(_ aNotification: Notification) {
  }

  @IBAction func quitClicked(_ sender: AnyObject) {
    NSApplication.shared.terminate(self)
  }

  @IBAction func prefsClicked(_ sender: AnyObject) {
    if let prefsController = prefsController {
      prefsController.showWindow(sender)
      NSApp.activate(ignoringOtherApps: true)
      prefsController.window?.makeKeyAndOrderFront(sender)
    }
  }

  /// Set the default prefs of the app
  func setDefaultPrefs() {
    let prefs = UserDefaults.standard
    if !prefs.bool(forKey: Utils.PrefKeys.appAlreadyLaunched.rawValue) {
      prefs.set(true, forKey: Utils.PrefKeys.appAlreadyLaunched.rawValue)

      prefs.set(false, forKey: Utils.PrefKeys.startAtLogin.rawValue)

      prefs.set(false, forKey: Utils.PrefKeys.showContrast.rawValue)
      prefs.set(false, forKey: Utils.PrefKeys.lowerContrast.rawValue)
    }
  }

  // MARK: - Menu

  func clearDisplays() {
    while statusMenu.items.count > 3 {
      statusMenu.removeItem(at: 0)
    }

    displays = []
  }

  func updateDisplays() {
    clearDisplays()

    let filteredScreens = NSScreen.screens.filter { screen -> Bool in
      if let id = screen.deviceDescription[NSDeviceDescriptionKey.init("NSScreenNumber")] as? CGDirectDisplayID {
        // Is Built In Screen (e.g. MBP/iMac Screen)
        if CGDisplayIsBuiltin(id) != 0 {
          return false
        }

        // Does screen support EDID ?
        var edid = EDID()
        if !EDIDTest(id, &edid) {
          return false
        }

        return true
      }
      return false
    }

    for screen in filteredScreens {
      self.addScreenToMenu(screen: screen)
    }

    if filteredScreens.count == 0 {
      // If no DDC capable display was detected
      let item = NSMenuItem()
      item.title = NSLocalizedString("No supported display found", comment: "Shown in menu")
      item.isEnabled = false
      statusMenu.insertItem(item, at: 0)
    }

    self.updateAudioOut()
  }

  /// Add a screen to the menu
  ///
  /// - Parameters:
  ///   - screen: The screen to add
  private func addScreenToMenu(screen: NSScreen) {
    if let id = screen.deviceDescription[NSDeviceDescriptionKey.init("NSScreenNumber")] as? CGDirectDisplayID {

      var edid = EDID()
      if EDIDTest(id, &edid) {
        let name = Utils.getDisplayName(forEdid: edid)
        let serial = Utils.getDisplaySerial(forEdid: edid)

        let display = Display.init(id, name: name, serial: serial)

        let monitorMenuItem = NSMenuItem()
        monitorMenuItem.title = "\(name)"

        Utils.addMenuItem(toMenu: statusMenu, item: NSMenuItem.separator())
        Utils.addMenuItem(toMenu: statusMenu, item: monitorMenuItem)

        let volumeSliderHandler = Utils.addSliderMenuItem(toMenu: statusMenu,
                                                          forDisplay: display,
                                                          command: AUDIO_SPEAKER_VOLUME,
                                                          title: "🔊")
        let brightnessSliderHandler = Utils.addSliderMenuItem(toMenu: statusMenu,
                                                              forDisplay: display,
                                                              command: BRIGHTNESS,
                                                              title: "🔆")
        if prefs.bool(forKey: Utils.PrefKeys.showContrast.rawValue) {
          let contrastSliderHandler = Utils.addSliderMenuItem(toMenu: statusMenu,
                                                              forDisplay: display,
                                                              command: CONTRAST,
                                                              title: "🔳")
          display.contrastSliderHandler = contrastSliderHandler
        }

        display.volumeSliderHandler = volumeSliderHandler
        display.brightnessSliderHandler = brightnessSliderHandler
        displays.append(display)
      }
    }
  }

  func updateAudioOut() {
    let defaultAudioOut = AudioCtrl.instance.defaultOutputName
    audioOutDisplay = nil
    for d in self.displays where d.name == defaultAudioOut {
      audioOutDisplay = d
      break
    }
    var keys: [MediaKey]
    if audioOutDisplay == nil {
      keys = AppDelegate.keysNoAudio
    } else {
      keys = AppDelegate.keysWithAudio
    }
    mediaKeyTap?.stop()
    mediaKeyTap = MediaKeyTap.init(delegate: self, for: keys, observeBuiltIn: false)
    mediaKeyTap?.start()
  }

  func onDefaultAudioOutputChange(_ name: String) {
    self.updateAudioOut()
  }

  // MARK: - Media Key Tap delegate

  func changeBrightness (_ amount: Int) {
    guard let currentDisplay = Utils.getCurrentDisplay(from: displays) else { return }
    let allDisplays = prefs.bool(forKey: Utils.PrefKeys.allScreens.rawValue) ? displays : [currentDisplay]
    for display in allDisplays {
      if (prefs.object(forKey: "\(display.identifier)-state") as? Bool) ?? true {
        let value = display.calcNewValue(for: BRIGHTNESS, withRel: amount)
        display.setBrightness(to: value)
      }
    }
  }

  func changeVolume (_ amount: Int) {
    guard let audioOutDisplay = self.audioOutDisplay else { return }
    if (prefs.object(forKey: "\(audioOutDisplay.identifier)-state") as? Bool) ?? true {
      let value = audioOutDisplay.calcNewValue(for: AUDIO_SPEAKER_VOLUME, withRel: amount)
      audioOutDisplay.setVolume(to: value)
    }
  }

  func handle(mediaKey: MediaKey, event: KeyEvent?) {
    switch mediaKey {
    case .brightnessUp:
      changeBrightness(+step)
    case .brightnessDown:
      changeBrightness(-step)
    case .mute:
      self.audioOutDisplay?.toggleMute()
    case .volumeUp:
      changeVolume(+step)
    case .volumeDown:
      changeVolume(-step)
    default:
      break
    }
  }

  @objc func handleShowContrastChanged() {
    self.updateDisplays()
  }
}
