import SwiftUI

struct BatteryDetailView: View {
    @EnvironmentObject var service: XiaohaCloudService
    @State private var showingConfigSheet = false
    @State private var selectedCellIndex: Int? = 11 // 默认选中 C12
    @State private var toastMessage: String?
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    
    var snapshot: XiaohaBatterySnapshot {
        service.currentSnapshot
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.10).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 14) {
                        headerSection
                        locationBanner
                        heroCard
                        threePillMetrics
                        cellMetricsGrid
                        bottomSpectrumCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
                
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(20)
                            .shadow(radius: 6)
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("小哈智电 (4G云端直连)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                let (ok, tip) = await service.ringBell()
                                showToast(tip)
                            }
                        } label: {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.cyan)
                        }
                        
                        Button {
                            showingConfigSheet = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingConfigSheet) {
                ConfigView()
                    .environmentObject(service)
            }
            .onAppear {
                Task {
                    await service.fetchRealtimeData(triggerWakeup: true)
                }
            }
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("编号:")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Text(snapshot.batterySn)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color(red: 0.08, green: 0.16, blue: 0.22))
                        .cornerRadius(4)
                }
                Text("型号: \(snapshot.batteryModel)/72V57AH · 4G云端优先")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("4G同步 \(formattedDate(snapshot.updateTime))")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(red: 0.09, green: 0.14, blue: 0.22))
            .cornerRadius(6)
        }
    }
    
    // MARK: - Location
    private var locationBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("📍 实时位置: \(snapshot.gpsAddress)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color(red: 0.88, green: 0.91, blue: 0.94))
                .lineLimit(2)
            
            Text(String(format: "🛰️ 4G/GPS坐标: %.5f°E, %.5f°N", snapshot.gpsLng, snapshot.gpsLat))
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.58, green: 0.64, blue: 0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(red: 0.07, green: 0.13, blue: 0.21))
        .cornerRadius(8)
        .onTapGesture {
            UIPasteboard.general.string = "\(snapshot.gpsAddress) (\(snapshot.gpsLng), \(snapshot.gpsLat))"
            showToast("已复制电池详细位置与坐标")
        }
    }
    
    // MARK: - Hero Card (SOC, Voltage, 3D Battery)
    private var heroCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                // SOC
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(snapshot.socPercent)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.0, green: 0.90, blue: 0.46))
                    Text("%")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 0.0, green: 0.90, blue: 0.46))
                }
                
                Rectangle()
                    .fill(Color(red: 0.0, green: 0.90, blue: 0.46))
                    .frame(width: 65, height: 3.5)
                
                // Pack Voltage
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.2f", snapshot.voltage))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("V")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.gray)
                }
                
                // Current & Status
                HStack(spacing: 8) {
                    Text(String(format: "%.2f A", snapshot.currentAmpere))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(snapshot.currentAmpere > 0.05 ? "⚡ 充电中" : (snapshot.currentAmpere < -0.05 ? "放电中" : (snapshot.mosSwitchOn ? "4G在线·待机" : "MOS已关断")))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(snapshot.currentAmpere < -0.05 ? .red : Color(red: 0.0, green: 0.90, blue: 0.46))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(snapshot.currentAmpere < -0.05 ? Color(red: 0.22, green: 0.10, blue: 0.13) : Color(red: 0.06, green: 0.16, blue: 0.12))
                        .cornerRadius(4)
                }
                
                // Delta & Power/Energy
                HStack(spacing: 12) {
                    Text("压差: \(snapshot.cellDiffMv) mV")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text("能耗: \(snapshot.officialEnergyConsumption)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 3D Battery Image
            ZStack {
                if snapshot.currentAmpere > 0.05 {
                    Image("battery_charging")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 190)
                } else {
                    Image("battery_official")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 190)
                }
            }
            .frame(width: 130)
            .onTapGesture {
                Task {
                    await service.fetchRealtimeData(triggerWakeup: true)
                    showToast("⚡ 已通过4G唤醒电池并刷新")
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Three Pill Metrics
    private var threePillMetrics: some View {
        HStack(spacing: 8) {
            pillCard(icon: "heart.fill", title: "电池健康度", value: "健康 \(snapshot.sohPercent)% (优)", color: .red)
            pillCard(icon: "battery.100", title: "剩余容量", value: String(format: "%.2f Ah", snapshot.capacityAh), color: .green)
            pillCard(icon: "arrow.triangle.2.circlepath", title: "累计循环", value: "\(snapshot.cycleCount)次 · 续航\(snapshot.officialEnduranceKm)", color: .cyan)
        }
    }
    
    private func pillCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundColor(.gray)
            }
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color(red: 0.08, green: 0.13, blue: 0.20))
        .cornerRadius(6)
    }
    
    // MARK: - Cell 4x5 Grid
    private var cellMetricsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("20串单体: 电压 · 容量Ah · 百分比 · 内阻")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Circle().fill(Color.cyan).frame(width: 7, height: 7)
                        Text("最高").font(.system(size: 10)).foregroundColor(.gray)
                    }
                    HStack(spacing: 3) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("最低").font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
            }
            
            // Selected hint bar
            if let idx = selectedCellIndex, idx < snapshot.cellVoltages.count {
                let mv = snapshot.cellVoltages[idx]
                let ah = idx < snapshot.cellCapacityAhs.count ? snapshot.cellCapacityAhs[idx] : snapshot.capacityAh
                let soc = idx < snapshot.cellSocPercents.count ? snapshot.cellSocPercents[idx] : Double(snapshot.socPercent)
                let r = idx < snapshot.cellResistances.count ? snapshot.cellResistances[idx] : 1.34
                let avg = Double(snapshot.cellVoltages.reduce(0, +)) / Double(snapshot.cellVoltages.count)
                let diff = Double(mv) - avg
                let sign = diff >= 0 ? "+\(String(format: "%.1f", diff))" : String(format: "%.1f", diff)
                
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                    Text(String(format: "No.%02d: %dmV | %.2fAh (%.1f%%) | 内阻 %.2fmΩ | 偏移 %@mV", idx + 1, mv, ah, soc, r, sign))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan)
                }
                .padding(.vertical, 2)
            }
            
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<snapshot.cellVoltages.count, id: \.self) { i in
                    cellItemView(index: i)
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.06, green: 0.10, blue: 0.15))
        .cornerRadius(10)
    }
    
    private func cellItemView(index: Int) -> some View {
        let mv = snapshot.cellVoltages[index]
        let isMax = (mv == snapshot.maxCellMv)
        let isMin = (mv == snapshot.minCellMv)
        let isSelected = (selectedCellIndex == index)
        
        let ah = index < snapshot.cellCapacityAhs.count ? snapshot.cellCapacityAhs[index] : snapshot.capacityAh
        let soc = index < snapshot.cellSocPercents.count ? snapshot.cellSocPercents[index] : Double(snapshot.socPercent)
        let r = index < snapshot.cellResistances.count ? snapshot.cellResistances[index] : 1.34
        
        let avg = Double(snapshot.cellVoltages.reduce(0, +)) / Double(snapshot.cellVoltages.count)
        let diff = Double(mv) - avg
        let diffStr = diff >= 0 ? "+\(String(format: "%.1f", diff))" : String(format: "%.1f", diff)
        
        return VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(String(format: "C%02d", index + 1))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isMin ? .orange : (isMax ? .cyan : .white))
                Spacer()
                Text(String(format: "%.1f%%", soc))
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 0.0, green: 0.85, blue: 0.45))
            }
            
            Text("\(mv)mV")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(isMin ? .orange : (isMax ? .cyan : .white))
            
            Text(String(format: "%.2fAh", ah))
                .font(.system(size: 9.5))
                .foregroundColor(Color(red: 0.35, green: 0.65, blue: 0.95))
            
            Text(String(format: "%.2fmΩ (%@)", r, diffStr))
                .font(.system(size: 8.5))
                .foregroundColor(.gray)
        }
        .padding(5)
        .background(Color(red: 0.04, green: 0.07, blue: 0.11))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.cyan : (isMin ? Color.orange : (isMax ? Color.cyan.opacity(0.6) : Color.white.opacity(0.08))), lineWidth: isSelected ? 1.5 : 1)
        )
        .cornerRadius(5)
        .onTapGesture {
            selectedCellIndex = index
        }
    }
    
    // MARK: - Bottom Spectrum Card
    private var bottomSpectrumCard: some View {
        HStack {
            Image(systemName: "chart.bar.xaxis")
                .foregroundColor(.cyan)
            Text("20串电压微压差图谱 & 阻值")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text("【极度均衡】AAA+")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 0.0, green: 0.90, blue: 0.46))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(red: 0.06, green: 0.16, blue: 0.12))
                .cornerRadius(4)
        }
        .padding(12)
        .background(Color(red: 0.06, green: 0.10, blue: 0.15))
        .cornerRadius(8)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func showToast(_ msg: String) {
        withAnimation {
            toastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                toastMessage = nil
            }
        }
    }
}
