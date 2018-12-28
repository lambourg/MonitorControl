//
//  Display.swift
//  MonitorControl
//
//  Created by Guillaume BRODER on 02/01/2018.
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
  var brightnessSliderHandler: SliderHandler?
  var volumeSliderHandler: SliderHandler?
  var contrastSliderHandler: SliderHandler?
  var bip: NSSound?

  private let prefs = UserDefaults.standard

  init(_ identifier: CGDirectDisplayID, name: String, serial: String, isEnabled: Bool = true) {
    self.identifier = identifier
    self.name = name
    self.serial = serial
    self.isEnabled = isEnabled
    self.bip = NSSound(named: "Pop")
  }

  func mute() {
    var value = 0
    if isMuted {
      value = prefs.integer(forKey: "\(AUDIO_SPEAKER_VOLUME)-\(identifier)")
      isMuted = false
    } else {
      isMuted = true
    }

    Utils.sendCommand(AUDIO_SPEAKER_VOLUME, toMonitor: identifier, withValue: value)
    if isMuted {
      //  Does not work on all monitors, but some do. So let's do both: put the volume to 0 (which may not be silent on some monitors) and use the mute command (which may not be supported on some monitors). This way we multiply the chances that at least one of those work
      Utils.sendCommand(AUDIO_MUTE, toMonitor: identifier, withValue: 1)
    } else {
      Utils.sendCommand(AUDIO_MUTE, toMonitor: identifier, withValue: 2)
    }
    if let slider = volumeSliderHandler?.slider {
      slider.intValue = Int32(value)
    }
    showOsd(command: AUDIO_SPEAKER_VOLUME, value: value)
    if !isMuted {
      bip?.stop()
      bip?.play()
    }
  }

  func setVolume(to value: Int) {
    if isMuted {
      self.mute()
    }

    Utils.sendCommand(AUDIO_SPEAKER_VOLUME, toMonitor: identifier, withValue: value)
    if let slider = volumeSliderHandler?.slider {
      slider.intValue = Int32(value)
    }
    showOsd(command: AUDIO_SPEAKER_VOLUME, value: value)
    saveValue(value, for: AUDIO_SPEAKER_VOLUME)

    bip?.stop()
    bip?.play()
  }

  func setBrightness(to value: Int) {
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
