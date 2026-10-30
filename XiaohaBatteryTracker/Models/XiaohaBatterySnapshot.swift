import Foundation

struct XiaohaCloudConfig: Codable, Equatable {
    var token: String = "635776bbd02a44bcb6098c5e4168413e"
    var deviceId: String = "8909092780"
    var guid: String = "1a8438a1512b41b58bb8ef96008fc463"
    var userNewId: String = "1295792169"
    var apiUrl: String = "https://switchpowerapi.hellobike.com"
}

struct XiaohaBatterySnapshot: Identifiable, Codable {
    var id: String = UUID().uuidString
    var success: Bool = true
    var batterySn: String = "8909092780"
    var batteryModel: String = "T71N"
    var voltage: Double = 85.17
    var socPercent: Int = 97
    var currentAmpere: Double = 0.0
    var capacityAh: Double = 55.29
    var ratedCapacityAh: Double = 57.0
    var cycleCount: Int = 7
    var sohPercent: Int = 100
    var temperatureCelsius: Double = 18.0
    var envTemp: Double = 21.0
    var mosTemp: Double = 19.0
    var probeTemps: [Double] = [18.0, 18.0, 18.0, 18.0]
    
    // 20串单体毫伏电压 (mV)
    var cellVoltages: [Int] = [
        4258, 4255, 4257, 4257, 4256, 4256, 4256, 4257, 4261, 4259,
        4257, 4260, 4257, 4260, 4260, 4259, 4262, 4261, 4258, 4260
    ]
    // 20串单体实时容量 (Ah)
    var cellCapacityAhs: [Double] = []
    // 20串单体百分比 (%)
    var cellSocPercents: [Double] = []
    // 20串单体内阻 (mΩ)
    var cellResistances: [Double] = []
    
    var packResistanceMilliOhm: Double = 27.2
    var maxCellMv: Int = 4262
    var minCellMv: Int = 4255
    var cellDiffMv: Int = 7
    
    var officialEnduranceKm: String = "142km"
    var officialTotalMileageKm: String = "1004km"
    var officialEnergyConsumption: String = "28wh/km"
    var mosSwitchOn: Bool = true
    var gpsAddress: String = "湖北省襄阳市樊城区人民西路梁坡工业园内襄阳山固建材有限公司"
    var gpsLat: Double = 32.06586
    var gpsLng: Double = 112.06911
    var hardwareReportTime: Int64 = 0
    var dataSource: String = "4G云端直连"
    var errorMessage: String = ""
    var updateTime: Date = Date()
    
    // 动态解算每串单体 Ah, SOC%, 内阻
    static func computePerCellMetrics(
        cellsMv: [Int],
        packSoc: Int,
        packRemainAh: Double,
        ratedAh: Double = 57.0,
        soh: Int = 100,
        cycles: Int = 7,
        probeTemps: [Double] = [18.0, 18.0, 18.0, 18.0]
    ) -> (ahs: [Double], socs: [Double], rs: [Double]) {
        let avgMv = cellsMv.isEmpty ? 4260.0 : Double(cellsMv.reduce(0, +)) / Double(cellsMv.count)
        let avgTemp = probeTemps.isEmpty ? 18.0 : probeTemps.reduce(0, +) / Double(probeTemps.count)
        let fullSpanMv = 1550.0
        let effectiveFullAh = ratedAh * (Double(min(100, max(50, soh))) / 100.0)
        
        var capList: [Double] = []
        var socList: [Double] = []
        var resList: [Double] = []
        
        let tempOffset = max(-10.0, 25.0 - avgTemp) * 0.006
        let agingOffset = Double(cycles) * 0.0015 + Double(100 - min(100, max(50, soh))) * 0.012
        let baseR = 1.30 + tempOffset + agingOffset
        
        for (i, mv) in cellsMv.enumerated() {
            let deltaMv = Double(mv) - avgMv
            let cSoc = min(100.0, max(0.0, Double(packSoc) + deltaMv / 15.5))
            let cAh = min(ratedAh, max(0.0, packRemainAh + (deltaMv / fullSpanMv) * effectiveFullAh))
            
            let probeIdx = i / 5
            let cellTemp = (probeIdx < probeTemps.count) ? probeTemps[probeIdx] : avgTemp
            let cellTempDiff = (avgTemp - cellTemp) * 0.004
            let voltImpedanceShift = min(0.05, max(-0.04, -deltaMv * 0.0035))
            let microVar = Double(((i * 7 + abs(mv)) % 5) - 2) * 0.003
            let cRes = min(2.50, max(1.15, baseR + voltImpedanceShift + cellTempDiff + microVar))
            
            capList.append((cAh * 100.0).rounded() / 100.0)
            socList.append((cSoc * 10.0).rounded() / 10.0)
            resList.append((cRes * 100.0).rounded() / 100.0)
        }
        
        return (capList, socList, resList)
    }
}
