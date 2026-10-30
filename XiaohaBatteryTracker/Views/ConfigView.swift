import SwiftUI

struct ConfigView: View {
    @EnvironmentObject var service: XiaohaCloudService
    @Environment(\.presentationMode) var presentationMode
    
    @State private var token: String = ""
    @State private var deviceId: String = ""
    @State private var guid: String = ""
    @State private var userNewId: String = ""
    @State private var rawJsonInput: String = ""
    @State private var showAlert = false
    @State private var alertMsg = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("小哈 4G 鉴权凭证")) {
                    TextField("电池 SN 编号 (如 89********)", text: $deviceId)
                    TextField("用户 Token", text: $token)
                    TextField("设备 GUID", text: $guid)
                    TextField("用户 userNewId", text: $userNewId)
                }
                
                Section(header: Text("一键粘贴抓包 JSON / 换机配置"), footer: Text("支持直接粘贴小哈小程序抓包参数或分享 JSON，自动识别填入。")) {
                    TextEditor(text: $rawJsonInput)
                        .frame(height: 100)
                    
                    Button("解析并自动填入") {
                        parseJson()
                    }
                }
                
                Section {
                    Button("保存并立即 4G 刷新") {
                        service.config.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        service.config.deviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
                        service.config.guid = guid.trimmingCharacters(in: .whitespacesAndNewlines)
                        service.config.userNewId = userNewId.trimmingCharacters(in: .whitespacesAndNewlines)
                        service.saveConfig()
                        
                        Task {
                            await service.fetchRealtimeData(triggerWakeup: true)
                        }
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
            .navigationTitle("小哈配置")
            .navigationBarItems(trailing: Button("完成") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                token = service.config.token
                deviceId = service.config.deviceId
                guid = service.config.guid
                userNewId = service.config.userNewId
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(alertMsg), dismissButton: .default(Text("好的")))
            }
        }
    }
    
    private func parseJson() {
        let text = rawJsonInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        if !text.hasPrefix("{") {
            token = text
            alertMsg = "已成功识别为纯 Token！"
            showAlert = true
            return
        }
        
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["token"] as? String ?? json["user-token"] as? String { token = t }
            if let g = json["guid"] as? String ?? json["userGuid"] as? String { guid = g }
            if let d = json["deviceId"] as? String ?? json["batteryNo"] as? String ?? json["batterySn"] as? String { deviceId = d }
            if let u = json["userNewId"] as? String ?? json["userId"] as? String { userNewId = u }
            alertMsg = "配置解析成功并已填入！"
            showAlert = true
        } else {
            alertMsg = "JSON 解析失败，请检查格式。"
            showAlert = true
        }
    }
}
