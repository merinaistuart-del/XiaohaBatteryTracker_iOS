import Foundation

class XiaohaCloudService: ObservableObject {
    @Published var config: XiaohaCloudConfig {
        didSet {
            saveConfig()
        }
    }
    @Published var currentSnapshot: XiaohaBatterySnapshot = XiaohaBatterySnapshot()
    @Published var isSyncing: Bool = false
    @Published var syncMessage: String = ""
    
    private let configKey = "xiaoha_cloud_config_key"
    private let snapshotKey = "xiaoha_battery_snapshot_key"
    
    init() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let saved = try? JSONDecoder().decode(XiaohaCloudConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = XiaohaCloudConfig()
        }
        
        if let snapData = UserDefaults.standard.data(forKey: snapshotKey),
           let savedSnap = try? JSONDecoder().decode(XiaohaBatterySnapshot.self, from: snapData) {
            self.currentSnapshot = savedSnap
        } else {
            var initial = XiaohaBatterySnapshot()
            let metrics = XiaohaBatterySnapshot.computePerCellMetrics(
                cellsMv: initial.cellVoltages,
                packSoc: initial.socPercent,
                packRemainAh: initial.capacityAh
            )
            initial.cellCapacityAhs = metrics.ahs
            initial.cellSocPercents = metrics.socs
            initial.cellResistances = metrics.rs
            self.currentSnapshot = initial
        }
    }
    
    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
    
    func saveSnapshot(_ snapshot: XiaohaBatterySnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }
    
    func fetchRealtimeData(triggerWakeup: Bool = true) async {
        guard !config.token.isEmpty else {
            await MainActor.run {
                self.syncMessage = "⚠️ 未配置小哈 Token"
            }
            return
        }
        
        await MainActor.run {
            self.isSyncing = true
            self.syncMessage = "🔄 4G云端同步中..."
        }
        
        let baseUrl = config.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if triggerWakeup {
            let wakeupExtra: [String: Any] = [
                "waitBatteryLifeCmdResultFlag": true,
                "cityCode": "0710",
                "batteries": [["batteryNo": config.deviceId]]
            ]
            _ = try? await postApi(baseUrl: baseUrl, action: "swp.li.user.battery.last", extraParams: wakeupExtra)
        }
        
        async let statusResp = postApi(baseUrl: baseUrl, action: "swp.li.user.battery.status")
        async let detailResp = postApi(baseUrl: baseUrl, action: "swp.li.user.battery.detail")
        async let trackResp = postApi(baseUrl: baseUrl, action: "swp.li.user.battery.track")
        async let mosResp = postApi(baseUrl: baseUrl, action: "swp.li.user.battery.getMosStatus")
        
        let statusJson = (try? await statusResp) ?? ""
        let detailJson = (try? await detailResp) ?? ""
        let trackJson = (try? await trackResp) ?? ""
        let mosJson = (try? await mosResp) ?? ""
        
        let merged = parseAndMerge(statusJson: statusJson, detailJson: detailJson, trackJson: trackJson, mosJson: mosJson)
        
        await MainActor.run {
            self.currentSnapshot = merged
            self.saveSnapshot(merged)
            self.isSyncing = false
            self.syncMessage = "✅ 4G同步成功 \(merged.voltage)V"
        }
    }
    
    func ringBell() async -> (Bool, String) {
        let baseUrl = config.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        do {
            let resp = try await postApi(baseUrl: baseUrl, action: "swp.li.user.battery.bell")
            if let data = resp.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["code"] as? Int, code == 0 {
                return (true, "🔔 寻车响铃已发送成功！")
            } else {
                return (false, "响应异常: \(resp)")
            }
        } catch {
            return (false, "发送失败: \(error.localizedDescription)")
        }
    }
    
    private func postApi(baseUrl: String, action: String, extraParams: [String: Any]? = nil) async throws -> String {
        guard let url = URL(string: "\(baseUrl)/api?action=\(action)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "token")
        request.setValue(config.token.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "user-token")
        request.setValue("LB64", forHTTPHeaderField: "systemCode")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.50", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0
        
        var body: [String: Any] = [
            "action": action,
            "batteryNo": config.deviceId,
            "batterySn": config.deviceId,
            "sn": config.deviceId,
            "deviceId": config.deviceId,
            "userId": config.userNewId.isEmpty ? config.guid : config.userNewId,
            "userGuid": config.guid,
            "token": config.token,
            "user-token": config.token,
            "systemCode": "LB64",
            "chaosChangeBattery": true,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        
        if let extra = extraParams {
            for (k, v) in extra {
                body[k] = v
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func parseAndMerge(statusJson: String, detailJson: String, trackJson: String, mosJson: String) -> XiaohaBatterySnapshot {
        var snap = currentSnapshot
        snap.updateTime = Date()
        
        // 解析 Status
        if let sData = statusJson.data(using: .utf8),
           let sObj = try? JSONSerialization.jsonObject(with: sData) as? [String: Any] {
            let data = (sObj["data"] as? [String: Any]) ?? sObj
            
            if let v = data["totalVoltage"] as? Double ?? data["voltage"] as? Double {
                snap.voltage = (v > 1000.0) ? v / 1000.0 : ((v > 200.0) ? v / 10.0 : v)
            }
            if let cur = data["current"] as? Double {
                snap.currentAmpere = cur
            }
            if let env = data["envTemperature"] as? Double ?? data["envTemp"] as? Double {
                snap.envTemp = env
            }
            if let mos = data["mosTemperature"] as? Double ?? data["mosTemp"] as? Double {
                snap.mosTemp = mos
            }
            if let p1 = data["batteryTemperatureOne"] as? Double,
               let p2 = data["batteryTemperatureTwo"] as? Double,
               let p3 = data["batteryTemperatureThree"] as? Double,
               let p4 = data["batteryTemperatureFour"] as? Double {
                snap.probeTemps = [p1, p2, p3, p4]
                snap.temperatureCelsius = (p1 + p2 + p3 + p4) / 4.0
            }
            if let cells = data["cellVoltageList"] as? [Double] ?? data["cellVoltages"] as? [Double] {
                snap.cellVoltages = cells.map { $0 < 10.0 ? Int(($0 * 1000.0).rounded()) : Int($0) }
            }
        }
        
        // 解析 Detail
        if let dData = detailJson.data(using: .utf8),
           let dObj = try? JSONSerialization.jsonObject(with: dData) as? [String: Any] {
            let data = (dObj["data"] as? [String: Any]) ?? dObj
            
            if let bType = data["batteryType"] as? String ?? data["batteryModel"] as? String {
                snap.batteryModel = bType
            }
            if let soc = data["batteryLife"] as? Int ?? data["soc"] as? Int ?? data["batteryPercent"] as? Int {
                snap.socPercent = soc
            }
            if let soh = data["soh"] as? Int ?? data["health"] as? Int {
                snap.sohPercent = soh
            }
            if let capStr = data["remainCapacity"] as? String {
                let clean = capStr.replacingOccurrences(of: "Ah", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                if let d = Double(clean) { snap.capacityAh = d }
            } else if let cap = data["capacity"] as? Double {
                snap.capacityAh = cap
            }
            if let chgStr = data["chargeCount"] as? String {
                let clean = chgStr.replacingOccurrences(of: "次", with: "").trimmingCharacters(in: .whitespaces)
                if let c = Int(clean) { snap.cycleCount = c }
            }
            if let end = data["endurance"] as? String { snap.officialEnduranceKm = end }
            if let tot = data["totalMileages"] as? String { snap.officialTotalMileageKm = tot }
            if let eng = data["energyConsumption"] as? String { snap.officialEnergyConsumption = eng }
        }
        
        // 解析 Track
        if let tData = trackJson.data(using: .utf8),
           let tObj = try? JSONSerialization.jsonObject(with: tData) as? [String: Any],
           let tDataObj = tObj["data"] as? [String: Any],
           let loc = tDataObj["location"] as? [String: Any] {
            
            let addr = loc["address"] as? String ?? ""
            let lat = loc["lat"] as? Double ?? 0.0
            let lng = loc["lng"] as? Double ?? 0.0
            
            if !addr.isEmpty {
                let isCoarse = addr.count <= 12 || addr.contains(" ")
                let prevDetailed = snap.gpsAddress.count > 12 && !snap.gpsAddress.contains(" ")
                if !(isCoarse && prevDetailed) {
                    snap.gpsAddress = addr
                }
            }
            if lat > 0 { snap.gpsLat = lat }
            if lng > 0 { snap.gpsLng = lng }
        }
        
        // 解析 MOS
        if let mData = mosJson.data(using: .utf8),
           let mObj = try? JSONSerialization.jsonObject(with: mData) as? [String: Any],
           let mDataObj = mObj["data"] as? [String: Any],
           let status = mDataObj["mosButtonStatus"] as? Int {
            snap.mosSwitchOn = (status == 1)
        }
        
        // 动态计算指标
        let maxV = snap.cellVoltages.max() ?? 4260
        let minV = snap.cellVoltages.min() ?? 4250
        snap.maxCellMv = maxV
        snap.minCellMv = minV
        snap.cellDiffMv = maxV - minV
        
        let metrics = XiaohaBatterySnapshot.computePerCellMetrics(
            cellsMv: snap.cellVoltages,
            packSoc: snap.socPercent,
            packRemainAh: snap.capacityAh,
            ratedAh: snap.ratedCapacityAh,
            soh: snap.sohPercent,
            cycles: snap.cycleCount,
            probeTemps: snap.probeTemps
        )
        snap.cellCapacityAhs = metrics.ahs
        snap.cellSocPercents = metrics.socs
        snap.cellResistances = metrics.rs
        snap.packResistanceMilliOhm = (metrics.rs.reduce(0, +) * 10.0).rounded() / 10.0
        
        return snap
    }
}
