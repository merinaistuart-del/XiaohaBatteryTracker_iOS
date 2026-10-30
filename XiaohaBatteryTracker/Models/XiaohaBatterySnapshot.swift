import Foundation

struct XiaohaCloudConfig: Codable, Equatable {
    var token: String = ""
    var deviceId: String = ""
    var guid: String = ""
    var userNewId: String = ""
    var apiUrl: String = "https://switchpowerapi.hellobike.com"
}

struct XiaohaBatterySnapshot: Identifiable, Codable {
    var id: String = UUID().uuidString
    var success: Bool = true
    var batterySn: String = "未绑定电池"
    var batteryModel: String = "T71N"
    var voltage: Double = 84.00
    var socPercent: Int = 100
    var currentAmpere: Double = 0.0
    var capacityAh: Double = 57.00
    var ratedCapacityAh: Double = 57.0
    var cycleCount: Int = 0
    var sohPercent: Int = 100
    var temperatureCelsius: Double = 20.0
    var envTemp: Double = 20.0
    var mosTemp: Double = 20.0
    var probeTemps: [Double] = [20.0, 20.0, 20.0, 20.0]
    
    var cellVoltages: [Int] = [
        4200, 4200, 4200, 4200, 4200, 4200, 4200, 4200, 4200, 4200,
        4200, 4200, 4200, 4200, 4200, 4200, 4200, 4200, 4200, 4200
    ]
    var cellCapacityAhs: [Double] = []
    var cellSocPercents: [Double] = []
    var cellResistances: [Double] = []
    
    var packResistanceMilliOhm: Double = 26.0
    var maxCellMv: Int = 4200
    var minCellMv: Int = 4200
    var cellDiffMv: Int = 0
    
    var officialEnduranceKm: String = "--km"
    var officialTotalMileageKm: String = "--km"
    var officialEnergyConsumption: String = "--wh/km"
    var mosSwitchOn: Bool = true
    var gpsAddress: String = "请在右上角设置中绑定您的电池 Token"
    var gpsLat: Double = 0.0
    var gpsLng: Double = 0.0
    var hardwareReportTime: Int64 = 0
    var dataSource: String = "4G云端直连"
    var errorMessage: String = ""
    var updateTime: Date = Date()
    
    static func computePerCellMetrics(
        cellsMv: [Int],
        packSoc: Int,
        packRemainAh: Double,
        ratedAh: Double = 57.0,
        soh: Int = 100,
        cycles: Int = 0,
        probeTemps: [Double] = [20.0, 20.0, 20.0, 20.0]
    ) -> (ahs: [Double], socs: [Double], rs: [Double]) {
        let avgMv = cellsMv.isEmpty ? 4200.0 : Double(cellsMv.reduce(0, +)) / Double(cellsMv.count)
        let avgTemp = probeTemps.isEmpty ? 20.0 : probeTemps.reduce(0, +) / Double(probeTemps.count)
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
            resList.append((cRes * 100.0).rounded() / 10.0)
        }
        
        return (capList, socList, resList)
    }
}
