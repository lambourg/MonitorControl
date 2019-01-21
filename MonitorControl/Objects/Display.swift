//
//  Display.swift
//  MonitorControl
//
//  Created by Guillaume BRODER on 02/01/2018.
//  Modified by Jerome Lambourg (12/2018)
//  MIT Licensed.
//

import Cocoa

/// A display
class Display {
  let identifier: CGDirectDisplayID
  let name: String
  let serial: String
  var isEnabled: Bool
  var isMuted: Bool = false
  var muteCmdSupported: Bool
  var brightnessSliderHandler: SliderHandler?
  var volumeSliderHandler: SliderHandler?
  var contrastSliderHandler: SliderHandler?
  let MIN_MUTE_VALUE = 3

  private let prefs = UserDefaults.standard

  init(_ identifier: CGDirectDisplayID, name: String, serial: String, isEnabled: Bool = true) {
    self.identifier = identifier
    self.name = name
    self.serial = serial
    self.isEnabled = isEnabled
    let previous = Utils.getCommand(AUDIO_MUTE, fromMonitor: identifier)
    self.muteCmdSupported = (previous == 1 || previous == 2)
  }

  func toggleMute() {
    isMuted = !isMuted
    print ("toggleMute: ", isMuted)

    let value: Int = isMuted ? 0 : self.loadValue(for: AUDIO_SPEAKER_VOLUME)

    if muteCmdSupported {
      let current = Utils.getCommand(AUDIO_MUTE, fromMonitor: identifier)
      if current != 1 && isMuted {
        Utils.sendCommand(AUDIO_MUTE, toMonitor: identifier, withValue: 1)
      } else if current != 2 && !isMuted {
        Utils.sendCommand(AUDIO_MUTE, toMonitor: identifier, withValue: 2)
      }
    } else {
      Utils.sendCommand(AUDIO_SPEAKER_VOLUME, toMonitor: identifier, withValue: value)
    }

    if let slider = volumeSliderHandler?.slider {
      slider.intValue = Int32(value)
    }
    print("  show OSD: ", value)
    showOsd(command: AUDIO_SPEAKER_VOLUME, value: value)
    if !isMuted {
      NSSound.beep()
    }
  }

  func setVolume(to value: Int, save: Bool = true) {
    print ("setVolume: ", value)
    saveValue(value, for: AUDIO_SPEAKER_VOLUME)

    var actual: Int

    if muteCmdSupported {
      if value >= MIN_MUTE_VALUE {
        actual = (value - MIN_MUTE_VALUE) * 100 / (100 - MIN_MUTE_VALUE)
        print("  set volume to ", actual)
        Utils.sendCommand(AUDIO_SPEAKER_VOLUME, toMonitor: identifier, withValue: actual)
        if isMuted {
          print("  unmute ", actual)
          Utils.sendCommand(AUDIO_MUTE, toMonitor: identifier, withValue: 2)
          isMuted = false
        }
        actual = value
      } else {
        actual = 0
        if !isMuted {
          print("  mute")
          Utils.sendCommand(AUDIO_MUTE, toMonitor: identifier, withValue: 1)
          isMuted = true
        }
      }
    } else {
      actual = value
      Utils.sendCommand(AUDIO_SPEAKER_VOLUME, toMonitor: identifier, withValue: value)
    }

    if let slider = volumeSliderHandler?.slider {
      slider.intValue = Int32(value)
    }
    print("  show OSD: ", actual)
    showOsd(command: AUDIO_SPEAKER_VOLUME, value: actual)

    NSSound.beep()
  }

  func setBrightness(to value: Int) {
    let value = min(100, max(0, value))
    if prefs.bool(forKey: Utils.PrefKeys.lowerContrast.rawValue) {
      if value == 0 {
        Utils.sendCommand(CONTRAST, toMonitor: identifier, withValue: value)
        if let slider = contrastSliderHandler?.slider {
          slider.intValue = Int32(value)
        }
      } else if prefs.integer(forKey: "\(BRIGHTNESS)-\(identifier)") == 0 {
        let contrastValue = prefs.integer(forKey: "\(CONTRAST)-\(identifier)")
        Utils.sendCommand(CONTRAST, toMonitor: identifier, withValue: contrastValue)
      }
    }

    Utils.sendCommand(BRIGHTNESS, toMonitor: identifier, withValue: value)
    if let slider = brightnessSliderHandler?.slider {
      slider.intValue = Int32(value)
    }
    showOsd(command: BRIGHTNESS, value: value)
    saveValue(value, for: BRIGHTNESS)
  }

  func calcNewValue(for command: Int32, withRel rel: Int) -> Int {
    let currentValue = prefs.integer(forKey: "\(command)-\(identifier)")
    return max(0, min(100, currentValue + rel))
  }

  func loadValue(for command: Int32) -> Int {
    return prefs.integer(forKey: "\(command)-\(identifier)")
  }
  func saveValue(_ value: Int, for command: Int32) {
    prefs.set(value, forKey: "\(command)-\(identifier)")
  }

  private func showOsd(command: Int32, value: Int) {
    if let manager = OSDManager.sharedManager() as? OSDManager {
      var osdImage: Int64 = 1 // Brightness Image
      if command == AUDIO_SPEAKER_VOLUME {
        osdImage = 3 // Speaker image
        if isMuted {
          osdImage = 4 // Mute speaker
        }
      }
      let step = 100/16
      manager.showImage(osdImage,
                        onDisplayID: identifier,
                        priority: 0x1f4,
                        msecUntilFade: 2000,
                        filledChiclets: UInt32(value/step),
                        totalChiclets: UInt32(100/step),
                        locked: false)
    }
  }
}
