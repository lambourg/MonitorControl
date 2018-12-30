//
//  Audio.swift
//  MonitorControl
//
//  Created by Jérôme Lambourg on 27/12/2018.
//  MIT Licensed.
//

import Foundation
import CoreAudio

public protocol AudioCtrlDelegate: class {
  func onDefaultAudioOutputChange(_ : String)
}

class AudioCtrl {
  static let instance = AudioCtrl()

  public var defaultOutputName: String = ""
  private var defaultDeviceName: String?
  weak var delegate: AudioCtrlDelegate?
  private static let outputChanged = NSNotification.Name("monitorcontrolAudioOutputDeviceChanged")

  static private var defaultOutputListener: AudioObjectPropertyListenerProc = {_, _, _, _ in
    NotificationCenter.default.post(name: AudioCtrl.outputChanged, object: nil)
    return 0
  }

  static private var outputDeviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMaster)

  static private var deviceNameAddress = AudioObjectPropertyAddress(
    mSelector: kAudioObjectPropertyName, //kAudioObjectPropertyName,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMaster)

  static private var deviceDataSourceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDataSource,
    mScope: kAudioObjectPropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMaster)
  static private var deviceDataSourceName = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
    mScope: kAudioObjectPropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMaster)

  private init() {
    // Listen to default output device change events
    AudioObjectAddPropertyListener(UInt32(kAudioObjectSystemObject),
                                   &AudioCtrl.outputDeviceAddress,
                                   AudioCtrl.defaultOutputListener,
                                   nil)
    NotificationCenter.default.addObserver(self, selector: #selector(AudioCtrl.handleNotification), name: AudioCtrl.outputChanged, object: nil)

    // Retrieve the current default AudioDeviceID
    handleNotification(nil)
  }

  deinit {
      AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                        &AudioCtrl.outputDeviceAddress,
                                        AudioCtrl.defaultOutputListener,
                                        nil)
  }

  public func registerDelegate(_ delegate: AudioCtrlDelegate) {
    self.delegate = delegate
  }

  @objc func handleNotification(_ notification: Notification?) {
    var size: UInt32 = 0
    var cfname: CFString = "" as CFString
    var defaultDevice: AudioDeviceID = 0
    var dataSourceId: UInt32 = 0

    //  Retrieve the ID of the default device
    size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(
      UInt32(kAudioObjectSystemObject),
      &AudioCtrl.outputDeviceAddress,
      0,
      nil,
      &size,
      &defaultDevice)

    // Retrieve the data source
    size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(
      defaultDevice,
      &AudioCtrl.deviceDataSourceAddress,
      0,
      nil,
      &size,
      &dataSourceId)

    //  And now retrieve the data source name
    var translation = AudioValueTranslation(
      mInputData: &dataSourceId,
      mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
      mOutputData: &cfname,
      mOutputDataSize: UInt32(MemoryLayout<CFString>.size))
    size = UInt32(MemoryLayout<AudioValueTranslation>.size)

    AudioObjectGetPropertyData(
      defaultDevice,
      &AudioCtrl.deviceDataSourceName,
      0,
      &dataSourceId,
      &size,
      &translation)
    defaultOutputName = cfname as String

    self.delegate?.onDefaultAudioOutputChange(defaultOutputName)
  }

}
