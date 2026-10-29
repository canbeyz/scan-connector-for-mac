// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit

enum ScanPalette {
    static let blue = Color(red: 0.09, green: 0.41, blue: 0.76)
    static let teal = Color(red: 0.08, green: 0.49, blue: 0.41)
    static let rail = Color(nsColor: .controlBackgroundColor)
}

struct ScannerIllustration: View {
    var active: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17).fill(ScanPalette.blue.opacity(0.07)).frame(width: 176, height: 146)
            Path { path in
                path.move(to: CGPoint(x: 55, y: 91)); path.addLine(to: CGPoint(x: 55, y: 31))
                path.addQuadCurve(to: CGPoint(x: 65,y:21),control: CGPoint(x:55,y:21))
                path.addLine(to:CGPoint(x:113,y:21)); path.addLine(to:CGPoint(x:131,y:40));path.addLine(to:CGPoint(x:131,y:91))
            }.fill(Color(nsColor: .windowBackgroundColor))
            Path { path in
                path.move(to:CGPoint(x:55,y:80));path.addLine(to:CGPoint(x:55,y:31));path.addQuadCurve(to:CGPoint(x:65,y:21),control:CGPoint(x:55,y:21));path.addLine(to:CGPoint(x:113,y:21));path.addLine(to:CGPoint(x:131,y:40));path.addLine(to:CGPoint(x:131,y:80))
                path.move(to:CGPoint(x:113,y:21));path.addLine(to:CGPoint(x:113,y:41));path.addLine(to:CGPoint(x:131,y:41))
                path.move(to:CGPoint(x:70,y:50));path.addLine(to:CGPoint(x:109,y:50));path.move(to:CGPoint(x:70,y:61));path.addLine(to:CGPoint(x:112,y:61))
            }.stroke(ScanPalette.blue.opacity(0.65),style:StrokeStyle(lineWidth:2,lineCap:.round,lineJoin:.round))
            RoundedRectangle(cornerRadius:9).fill(Color(nsColor:.windowBackgroundColor)).overlay(RoundedRectangle(cornerRadius:9).stroke(ScanPalette.blue,lineWidth:2)).frame(width:132,height:48).offset(y:24)
            Capsule().fill(ScanPalette.blue.opacity(0.13)).frame(width:98,height:6).offset(y:14)
            Circle().fill(active ? ScanPalette.teal : Color.secondary.opacity(0.4)).frame(width:5,height:5).offset(x:48,y:29)
            RoundedRectangle(cornerRadius:2).fill(ScanPalette.blue.opacity(0.65)).frame(width:72,height:3).offset(y:43)
        }.frame(width:176,height:146).accessibilityHidden(true)
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width:218)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom,24)
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        deviceSection
                        Divider()
                        destinationSection
                        Divider()
                        preferencesSection
                        Divider()
                        startupSection
                        if !model.errorText.isEmpty { errorView }
                        lastScanRow
                    }.padding(.bottom,18)
                }
                .scrollIndicators(.visible)
                .disabled(model.connecting || model.applying || model.registering || model.scanning)
                Divider()
                controls.padding(.top,18)
            }.padding(28)
        }
        .frame(minWidth:880,minHeight:650)
        .background(Color(nsColor:.windowBackgroundColor))
        .tint(ScanPalette.blue)
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:9) {
                Image(systemName:"scanner").font(.system(size:21,weight:.medium)).foregroundStyle(ScanPalette.blue)
                Text("Scan Connector\nfor Mac").font(.system(size:17,weight:.semibold)).lineSpacing(1)
            }.padding(.bottom,6)
            Text("Community app").font(.system(size:10)).foregroundStyle(.secondary).padding(.bottom,26)
            ScannerIllustration(active:model.registered || model.scanning).padding(.leading,-2).padding(.bottom,22)
            HStack(spacing:7) {
                Circle().fill(model.registered ? ScanPalette.teal : (model.connected ? ScanPalette.blue : Color.secondary.opacity(0.5))).frame(width:7,height:7)
                Text(model.statusTitle).font(.system(size:13,weight:.medium))
            }.padding(.bottom,9)
            Text(model.stateText).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(4)
            Spacer(minLength:24)
            VStack(alignment:.leading,spacing:9) {
                Label("Local network scanning",systemImage:"wifi").font(.system(size:12))
                Text("Scan from the printer while this Mac is awake.").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Divider().padding(.vertical,16)
            Button { model.showFolder() } label: { Label("Open Scan Folder",systemImage:"folder").font(.system(size:12)) }.buttonStyle(.plain)
        }.padding(.horizontal,22).padding(.top,30).padding(.bottom,25)
        .background(ScanPalette.rail)
    }
    var header: some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:6) {
                Text("Receive scans").font(.system(size:27,weight:.semibold))
                Text("Choose this Mac's printer destination name and save location.")
                    .font(.system(size:13)).foregroundStyle(.secondary)
                Text("Independent community software").font(.system(size:11)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.connecting || model.applying || model.registering || model.scanning { ProgressView().controlSize(.small).padding(.top,8) }
        }
    }
    var deviceSection: some View {
        VStack(alignment:.leading,spacing:13) {
            sectionTitle("Printer",symbol:"printer")
            PrinterSelectionView(model:model,discovery:model.discovery)
            HStack(spacing:9) {
                Image(systemName:model.connected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.connected ? ScanPalette.teal : Color.secondary)
                VStack(alignment:.leading,spacing:3) {
                    Text(model.model).font(.system(size:13,weight:.medium))
                    if !model.ip.isEmpty { Text(model.ip).font(.system(size:11)).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Spacer()
                Button("Check Connection") { Task { await model.connect(startReceiving:model.settings.receiveEnabled) } }
                    .disabled(model.connecting || model.applying || model.scanning || model.settings.printerHost.isEmpty)
                    .help("Check the printer connection again")
            }.padding(.top,2)
        }
    }
    var destinationSection: some View {
        VStack(alignment:.leading,spacing:14) {
            sectionTitle("This Mac",symbol:"desktopcomputer")
            VStack(alignment:.leading,spacing:6) {
                HStack {
                    Text("Destination").font(.system(size:13)).frame(width:80,alignment:.leading)
                    TextField("e.g. Office Mac",text:$model.settings.displayName)
                        .textFieldStyle(.roundedBorder).disabled(model.scanning || model.connecting || model.applying || model.registering).accessibilityLabel("Printer display name")
                    Text("\(model.settings.displayName.count)/\(AppSettings.maxDisplayNameLength)")
                        .font(.system(size:11).monospacedDigit()).foregroundStyle(model.settings.nameIsValid ? Color.secondary : Color.orange)
                }
                Text("Up to 15 ASCII letters, digits, spaces, - or _. No leading or trailing spaces.")
                    .font(.system(size:11)).foregroundStyle(model.settings.nameIsValid ? Color.secondary : Color.orange)
                    .padding(.leading,84)
            }
            HStack(alignment:.center,spacing:10) {
                Text("Save to").font(.system(size:13)).frame(width:70,alignment:.leading)
                Image(systemName:"folder.fill").foregroundStyle(ScanPalette.blue.opacity(0.8))
                Text(model.settings.outputPath.replacingOccurrences(of:NSHomeDirectory(),with:"~"))
                    .font(.system(size:12)).lineLimit(1).truncationMode(.middle).help(model.settings.outputPath)
                Spacer(minLength:0)
                Button("Change…") { model.chooseFolder() }.disabled(model.scanning)
            }
            HStack {
                Spacer()
                Button("Apply Settings") { model.applySettings() }.disabled(!model.settings.nameIsValid || model.connecting || model.applying || model.scanning || model.settings.printerHost.isEmpty)
            }
        }
    }
    var preferencesSection: some View {
        VStack(alignment:.leading,spacing:14) {
            sectionTitle("Scan appearance",symbol:"slider.horizontal.3")
            HStack(alignment:.center,spacing:18) {
            VStack(alignment:.leading,spacing:7) {
                Text("Resolution").font(.system(size:12)).foregroundStyle(.secondary)
                Picker("Resolution",selection:$model.settings.dpi) {
                    Text("200 dpi").tag(200);Text("300 dpi · Standard").tag(300);Text("600 dpi · Fine").tag(600)
                }.labelsHidden().frame(width:165).disabled(model.scanning).onChange(of:model.settings.dpi) { _ in model.save() }
            }
            VStack(alignment:.leading,spacing:7) {
                Text("Paper source").font(.system(size:12)).foregroundStyle(.secondary)
                Picker("Paper source",selection:$model.settings.source) {
                    Text("Automatic").tag("auto");Text("Flatbed").tag("platen");Text("Document feeder").tag("adf")
                }.labelsHidden().frame(width:155).disabled(model.scanning).onChange(of:model.settings.source) { _ in model.save() }
            }
            Spacer()
            Text("PDF output").font(.system(size:12)).foregroundStyle(.secondary).padding(.top,20)
            }
            HStack(spacing:12) {
                Text("Color mode").font(.system(size:12)).frame(width:70,alignment:.leading)
                Picker("Color mode",selection:$model.settings.colorMode) {
                    ForEach(ScanColorMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.labelsHidden().pickerStyle(.segmented).onChange(of:model.settings.colorMode) { _ in model.save() }
            }
            Toggle("Enhance documents: darken faint text and clean up paper tones",isOn:$model.settings.documentEnhancement)
                .font(.system(size:12)).onChange(of:model.settings.documentEnhancement) { _ in model.save() }
            toneSlider("Density",value:Binding(get:{Double(model.settings.density)},set:{model.settings.density=Int($0)}),number:model.settings.density,low:"Light",high:"Dark")
            toneSlider("Contrast",value:Binding(get:{Double(model.settings.contrast)},set:{model.settings.contrast=Int($0)}),number:model.settings.contrast,low:"Low",high:"High")
            if model.settings.colorMode == .text {
                HStack(spacing:12) {
                    Text("Text threshold").font(.system(size:12)).frame(width:70,alignment:.leading)
                    Slider(value:Binding(get:{Double(model.settings.textThreshold)},set:{model.settings.textThreshold=Int($0)}),in:64...240,step:1) { _ in model.save() }
                    Text("\(model.settings.textThreshold)").font(.system(size:11).monospacedDigit()).frame(width:30)
                }
                Text("Higher values turn more light-gray detail black. Best for documents and receipts; use Color or Grayscale for photos.")
                    .font(.system(size:11)).foregroundStyle(.secondary)
            }
            HStack {
                Text("Turn off enhancement for photos or to preserve original tones.").font(.system(size:11)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset Tones") { model.settings.documentEnhancement=false;model.settings.density=0;model.settings.contrast=0;model.save() }.controlSize(.small)
            }
        }
    }
    func toneSlider(_ title:String,value:Binding<Double>,number:Int,low:String,high:String) -> some View {
        HStack(spacing:12) {
            Text(title).font(.system(size:12)).frame(width:70,alignment:.leading)
            Text(low).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).frame(width:34)
            Slider(value:value,in:-50...50,step:1) { _ in model.save() }
            Text(high).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).frame(width:34)
            Text(number > 0 ? "+\(number)" : "\(number)").font(.system(size:11).monospacedDigit()).frame(width:30)
        }
    }
    var startupSection: some View {
        VStack(alignment:.leading,spacing:10) {
            sectionTitle("Automatic reception",symbol:"arrow.triangle.2.circlepath")
            Toggle("Receive scans automatically when the app opens",isOn:$model.settings.automaticReception)
                .font(.system(size:12)).onChange(of:model.settings.automaticReception) { _ in model.save() }
            Toggle("Launch in the background at login",isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)}))
                .font(.system(size:12))
            Text("Keep receiving from the menu bar after closing this window. Pause lasts for this session. Reconnects after wake or network recovery.")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    var lastScanRow: some View {
        HStack(spacing:10) {
            Image(systemName:"doc.text").foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:3) {
                Text(model.scanning ? "Received \(pageSummary(model.pagesReceived))" : model.lastScanText).font(.system(size:12))
                if let url = model.lastScan { Text(url.lastPathComponent).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            Spacer()
            if let url = model.lastScan {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.controlSize(.small)
            }
        }.padding(.top,2)
    }
    var errorView: some View {
        HStack(alignment:.top,spacing:9) {
            Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(model.errorText).font(.system(size:12)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
            Spacer(minLength:0)
            Button { model.errorText = "" } label: { Image(systemName:"xmark").font(.system(size:10)) }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(12).background(Color.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:7))
    }
    var controls: some View {
        HStack(spacing:12) {
            Text(model.settings.automaticReception ? "Auto receive on launch" : "Auto receive is off").font(.system(size:11)).foregroundStyle(.secondary)
            Spacer()
            if model.scanning {
                Button("Cancel Scan") { model.cancelScan() }
            } else {
                Button("Scan Now") { model.performScan() }.disabled(!model.connected || model.connecting)
                Button(model.registered ? "Pause Receiving" : "Start Receiving") {
                    if model.registered { model.pauseReceiving() } else { model.startReceiving() }
                }.buttonStyle(.borderedProminent).disabled(!model.canReceive).keyboardShortcut(.return,modifiers:[])
            }
        }
    }
    func sectionTitle(_ text:String,symbol:String) -> some View {
        HStack(spacing:7) { Image(systemName:symbol).font(.system(size:13));Text(text).font(.system(size:14,weight:.semibold)) }
    }
}

struct PrinterSelectionView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var discovery: PrinterDiscovery
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:9) {
                Picker("Select printer",selection:Binding(get:{model.settings.printerHost},set:{host in
                    if let printer = discovery.printers.first(where:{$0.host == host}) { model.choose(printer) }
                })) {
                    Text("Select a Brother printer on your network").tag("")
                    ForEach(discovery.printers) { printer in Text(printer.name).tag(printer.host) }
                    if !model.settings.printerHost.isEmpty && !discovery.printers.contains(where:{$0.host == model.settings.printerHost}) {
                        Text(model.settings.printerName.isEmpty ? model.settings.printerHost : model.settings.printerName).tag(model.settings.printerHost)
                    }
                }.labelsHidden().disabled(model.scanning || model.connecting || model.applying)
                Button { discovery.start() } label: {
                    if discovery.searching { ProgressView().controlSize(.mini).frame(width:13,height:13) }
                    else { Image(systemName:"arrow.clockwise") }
                }.help("Search for printers again").accessibilityLabel("Search for printers again")
                Menu {
                    Button("Forget This Printer") { model.forgetPrinter() }.disabled(model.settings.printerHost.isEmpty || model.scanning || model.connecting || model.applying)
                } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().help("Printer options")
            }
            DisclosureGroup("Enter an address manually",isExpanded:$model.manualAddressExpanded) {
                HStack {
                    TextField("e.g. 192.0.2.10 or printer.local",text:Binding(get:{model.settings.printerHost},set:{model.changePrinterHost($0)})).textFieldStyle(.roundedBorder).accessibilityLabel("Printer address")
                    Button("Connect") { Task { await model.connect(startReceiving:model.settings.receiveEnabled) } }.disabled(model.connecting || model.scanning)
                }.padding(.top,6)
            }.font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
}
