//
//  PolarBleSdkManager.swift
//  FD-dataset-generator
//
//  Created by Harry Wixley on 18/12/2021.
//

import Foundation
import PolarBleSdk
import RxSwift
import CoreBluetooth

class PolarBleSdkManager : ObservableObject {
    
    // NOTICE this example utilizes all available features
    private var api = PolarBleApiDefaultImpl.polarImplementation(DispatchQueue.main, features: Features.allFeatures.rawValue)
    private var broadcastDisposable: Disposable?
    private var autoConnectDisposable: Disposable?
    private var searchDisposable: Disposable?
    private var ecgDisposable: Disposable?
    private var accDisposable: Disposable?
    private var ppgDisposable: Disposable?
    private var ppiDisposable: Disposable?
    private var deviceId = MyConstants.polarDeviceID
    
    @Published private(set) var bluetoothPowerOn: Bool
    @Published private(set) var broadcastEnabled: Bool = false
    @Published private(set) var seachEnabled: Bool = false
    @Published private(set) var ecgEnabled: Bool = false
    @Published private(set) var accEnabled: Bool = false
    @Published private(set) var gyroEnabled: Bool = false
    @Published private(set) var magnetometerEnabled: Bool = false
    @Published private(set) var ppgEnabled: Bool = false
    @Published private(set) var ppiEnabled: Bool = false
    @Published private(set) var sdkModeEnabled: Bool = false
    @Published private(set) var deviceConnectionState: ConnectionState = ConnectionState.disconnected
    
    //MARK: Data variables
    @Published var ecg: [Double] = []
    @Published var acc_x: [Double] = []
    @Published var acc_y: [Double] = []
    @Published var acc_z: [Double] = []
    @Published var hr: [Double] = []
    @Published var contact : [Bool] = []
    
    @Published var l_ecg: Int32 = 0
    @Published var l_acc_x: Int32 = 0
    @Published var l_acc_y: Int32 = 0
    @Published var l_acc_z: Int32 = 0
    @Published var l_hr: UInt8 = 0
    @Published var l_hr_rrsms : Int = 0
    @Published var l_hr_rrs : Int = 0
    
    @Published var battery : UInt = -1
    
    
    //MARK: Status variables
    @Published var isRecording: Bool = false {
        didSet {
            if isRecording {
                self.ecg = []
                self.acc_x = []
                self.acc_y = []
                self.acc_z = []
                self.contact = []
            }
        }
    }
    @Published var isLive: Bool = false {
        didSet {
            if isLive {
                self.l_ecg = 0
                self.l_hr = 0
                self.l_acc_x = 0
                self.l_acc_y = 0
                self.l_acc_z = 0
                self.l_hr_rrs = 0
                self.l_hr_rrsms = 0
            }
        }
    }
    
    
    init() {
        self.bluetoothPowerOn = api.isBlePowered
        
        api.polarFilter(true)
        api.observer = self
        api.deviceFeaturesObserver = self
        api.powerStateObserver = self
        api.deviceInfoObserver = self
        api.sdkModeFeatureObserver = self
        api.deviceHrObserver = self
        api.logger = self
    }
    
    func broadcastToggle() {
        if broadcastEnabled == false {
            broadcastDisposable = api.startListenForPolarHrBroadcasts(nil)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .completed:
                        self.broadcastEnabled = false
                        NSLog("Broadcast listener completed")
                    case .error(let err):
                        self.broadcastEnabled = false
                        NSLog("Broadcast listener failed. Reason: \(err)")
                    case .next(let broadcast):
                        self.broadcastEnabled = true
                        NSLog("HR BROADCAST \(broadcast.deviceInfo.name) HR:\(broadcast.hr) Batt: \(broadcast.batteryStatus)")
                    }
                }
        } else {
            broadcastEnabled = false
            broadcastDisposable?.dispose()
        }
    }
    
    func connectToDevice() {
        do {
            try api.connectToDevice(deviceId)
        } catch let err {
            print("Failed to connect. Reason \(err)")
            NSLog("Failed to connect to \(deviceId). Reason \(err)")
        }
    }
    
    func disconnectFromDevice() {
        if case .connected(let deviceId) = deviceConnectionState {
            do {
                try api.disconnectFromDevice(deviceId)
            } catch let err {
                NSLog("Failed to disconnect from \(deviceId). Reason \(err)")
            }
        }
    }
    
    func autoConnect() {
        autoConnectDisposable?.dispose()
        autoConnectDisposable = api.startAutoConnectToDevice(-55, service: nil, polarDeviceType: nil)
            .subscribe{ e in
                switch e {
                case .completed:
                    NSLog("auto connect search complete")
                case .error(let err):
                    NSLog("auto connect failed: \(err)")
                }
            }
    }
    
    func searchToggle() {
        if searchDisposable == nil {
            seachEnabled = true
            searchDisposable = api.searchForDevice()
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .completed:
                        NSLog("search complete")
                        self.seachEnabled = false
                    case .error(let err):
                        NSLog("search error: \(err)")
                        self.seachEnabled = false
                    case .next(let item):
                        NSLog("polar device found: \(item.name) connectable: \(item.connectable) address: \(item.address.uuidString)")
                    }
                }
        } else {
            seachEnabled = false
            searchDisposable?.dispose()
            searchDisposable = nil
        }
    }
    
    func ecgToggle() {
        if ecgDisposable == nil, case .connected(let deviceId) = deviceConnectionState {
            ecgEnabled = true
            ecgDisposable = api.requestStreamSettings(deviceId, feature: DeviceStreamingFeature.ecg)
                .asObservable()
                .flatMap({ (settings) -> Observable<PolarEcgData> in
                    return self.api.startEcgStreaming(self.deviceId, settings: settings.maxSettings())
                })
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .next(let data):
                        for µv in data.samples {
                            if self.isRecording {
                                self.ecg.append(Double(µv))
                            }
                            if self.isLive {
                                self.l_ecg = µv
                            }
                            //NSLog("    µV: \(µv)")
                        }
                    case .error(let err):
                        NSLog("ECG stream failed: \(err)")
                        self.ecgEnabled = false
                    case .completed:
                        NSLog("ECG stream completed")
                        self.ecgEnabled = false
                    }
                }
        } else {
            ecgEnabled = false
            ecgDisposable?.dispose()
            ecgDisposable = nil
        }
    }
    
    func accToggle() {
        if accDisposable == nil, case .connected(let deviceId) = deviceConnectionState {
            accEnabled = true
            accDisposable = api.requestStreamSettings(deviceId, feature: DeviceStreamingFeature.acc)
                .asObservable()
                .flatMap({ (settings) -> Observable<PolarAccData> in
                    NSLog("settings: \(settings.settings)")
                    return self.api.startAccStreaming(self.deviceId, settings: settings.maxSettings())
                })
                .observe(on: MainScheduler.instance).subscribe{ e in
                    switch e {
                    case .next(let data):
                        for item in data.samples {
                            if self.isRecording {
                                self.acc_x.append(Double(item.x))
                                self.acc_y.append(Double(item.y))
                                self.acc_z.append(Double(item.z))
                            }
                            if self.isLive {
                                self.l_acc_x = item.x
                                self.l_acc_y = item.y
                                self.l_acc_z = item.z
                            }
                            //NSLog("    x: \(item.x) y: \(item.y) z: \(item.z)")
                        }
                    case .error(let err):
                        NSLog("ACC stream failed: \(err)")
                        self.accEnabled = false
                    case .completed:
                        NSLog("ACC stream completed")
                        self.accEnabled = false
                        break
                    }
                }
        } else {
            accEnabled = false
            accDisposable?.dispose()
            accDisposable = nil
        }
    }

    
    func ppgToggle() {
        if ppgDisposable == nil, case .connected(let deviceId) = deviceConnectionState {
            ppgEnabled = true
            ppgDisposable = api.requestStreamSettings(deviceId, feature: DeviceStreamingFeature.ppg)
                .asObservable()
                .flatMap({ (settings) -> Observable<PolarOhrData> in
                    return self.api.startOhrStreaming(self.deviceId, settings: settings.maxSettings())
                })
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .next(let data):
                        if(data.type == OhrDataType.ppg3_ambient1) {
                            for item in data.samples {
                                //NSLog("    ppg0: \(item[0]) ppg1: \(item[1]) ppg2: \(item[2]) ambient: \(item[3])")
                            }
                        }
                    case .error(let err):
                        NSLog("PPG stream failed: \(err)")
                        self.ppgEnabled = false
                    case .completed:
                        NSLog("PPG stream completed")
                        self.ppgEnabled = false
                    }
                }
        } else {
            ppgEnabled = false
            ppgDisposable?.dispose()
            ppgDisposable = nil
        }
    }
    
    func ppiToggle() {
        if ppiDisposable == nil, case .connected(let deviceId) = deviceConnectionState {
            ppiEnabled = true
            ppiDisposable = api.startOhrPPIStreaming(deviceId)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .next(let data):
                        /*for item in data.samples {
                            //NSLog("    PPI: \(item.ppInMs) sample.blockerBit: \(item.blockerBit)  errorEstimate: \(item.ppErrorEstimate)")
                        }*/
                    case .error(let err):
                        NSLog("PPI stream failed: \(err)")
                        self.ppiEnabled = false
                    case .completed:
                        NSLog("PPI stream completed")
                        self.ppiEnabled = false
                    }
                }
        } else {
            ppiEnabled = false
            ppiDisposable?.dispose()
            ppiDisposable = nil
        }
    }
   
    func sdkModeEnable() {
        if case .connected(let deviceId) = deviceConnectionState {
            _ = api.enableSDKMode(deviceId)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .completed:
                        NSLog("SDK mode enabled")
                        self.sdkModeEnabled = true
                    case .error(let err):
                        NSLog("SDK mode enable failed: \(err)")
                    }
                }
        }
    }
    
    func sdkModeDisable() {
        if case .connected(let deviceId) = deviceConnectionState {
            _ = api.disableSDKMode(deviceId)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .completed:
                        NSLog("SDK mode disabled")
                        self.sdkModeEnabled = false
                    case .error(let err):
                        NSLog("SDK mode disable failed: \(err)")
                    }
                }
        }
    }
    
    func startH10Recording() {
        if case .connected(let deviceId) = deviceConnectionState {
            _ = api.startRecording(deviceId, exerciseId: "TEST_APP_ID", interval: .interval_1s, sampleType: .rr)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .completed:
                        NSLog("recording started")
                    case .error(let err):
                        NSLog("recording start fail: \(err)")
                    }
                }
        }
    }
    
    func stopH10Recording() {
        if case .connected(let deviceId) = deviceConnectionState {
            _ = api.stopRecording(deviceId)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .completed:
                        NSLog("recording stopped")
                    case .error(let err):
                        NSLog("recording stop fail: \(err)")
                    }
                }
        }
    }
    
    func getH10RecordingStatus() {
        if case .connected(let deviceId) = deviceConnectionState {
            _ = api.requestRecordingStatus(deviceId)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .failure(let err):
                        NSLog("recording status request failed: \(err)")
                    case .success(let pair):
                        NSLog("recording on: \(pair.ongoing) id: \(pair.entryId)")
                    }
                }
        }
    }
    
    func setTime() {
        if case .connected(let deviceId) = deviceConnectionState {
            let time = Date()
            let timeZone = TimeZone.current
            _ = api.setLocalTime(deviceId, time: time, zone: timeZone)
                .observe(on: MainScheduler.instance)
                .subscribe{ e in
                    switch e {
                    case .completed:
                        NSLog("time set to device completed")
                    case .error(let err):
                        NSLog("time set failed: \(err)")
                    }
                }
        }
    }
}

// MARK: - PolarBleApiPowerStateObserver
extension PolarBleSdkManager: PolarBleApiPowerStateObserver {
    func blePowerOn() {
        bluetoothPowerOn = true
    }
    
    func blePowerOff() {
        bluetoothPowerOn = false
    }
}

// MARK: - PolarBleApiObserver
extension PolarBleSdkManager : PolarBleApiObserver {
    func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DEVICE CONNECTING: \(polarDeviceInfo)")
        deviceConnectionState = ConnectionState.connecting(polarDeviceInfo.deviceId)
    }
    
    func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DEVICE CONNECTED: \(polarDeviceInfo)")
        deviceConnectionState = ConnectionState.connected(polarDeviceInfo.deviceId)
    }
    
    func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DISCONNECTED: \(polarDeviceInfo)")
        deviceConnectionState = ConnectionState.disconnected
        self.sdkModeEnabled = false
    }
}

// MARK: - PolarBleApiDeviceInfoObserver
extension PolarBleSdkManager : PolarBleApiDeviceInfoObserver {
    func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        NSLog("battery level updated: \(batteryLevel)")
    }
    
    func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
        NSLog("dis info: \(uuid.uuidString) value: \(value)")
    }
}

// MARK: - PolarBleApiSdkModeFeatureObserver
extension PolarBleSdkManager : PolarBleApiDeviceFeaturesObserver {
    func hrFeatureReady(_ identifier: String) {
        NSLog("HR ready")
    }
    
    func ftpFeatureReady(_ identifier: String) {
        NSLog("FTP ready")
    }
    
    func streamingFeaturesReady(_ identifier: String, streamingFeatures: Set<DeviceStreamingFeature>) {
        for feature in streamingFeatures {
            NSLog("Feature \(feature) is ready.")
        }
    }
}

// MARK: - PolarBleApiSdkModeFeatureObserver
extension PolarBleSdkManager : PolarBleApiSdkModeFeatureObserver {
    func sdkModeFeatureAvailable(_ identifier: String) {
        NSLog("SDK mode feature available. Device \(identifier)")
    }
}

// MARK: - PolarBleApiDeviceHrObserver
extension PolarBleSdkManager : PolarBleApiDeviceHrObserver {
    func hrValueReceived(_ identifier: String, data: PolarHrData) {
        if self.isRecording {
            self.hr.append(Double(data.hr))
            self.contact.append(data.contact)
        }
        if self.isLive {
            self.l_hr = data.hr
            if data.rrs.count > 0 {
                self.l_hr_rrs = data.rrs.count == 1 ? data.rrs[0] : data.rrs[1]
            }
            if data.rrsMs.count > 0 {
                self.l_hr_rrsms = data.rrsMs.count == 1 ? data.rrsMs[0] : data.rrsMs[1]
            }
        }
        //NSLog("(\(identifier)) HR value: \(data.hr) rrsMs: \(data.rrsMs) rrs: \(data.rrs) contact: \(data.contact) contact supported: \(data.contactSupported)")
    }
}

// MARK: - PolarBleApiLogger
extension PolarBleSdkManager : PolarBleApiLogger {
    func message(_ str: String) {
        //NSLog("Polar SDK log:  \(str)")
    }
}

extension PolarBleSdkManager {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting(String)
        case connected(String)
    }
}
