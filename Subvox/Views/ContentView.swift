import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            List(AppModel.Screen.allCases, selection: screenSelection) { screen in
                Label(screen.rawValue, systemImage: screen.symbol).tag(screen)
            }
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
            detail
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                MotionStatusBadge(status: model.motion.status, rate: model.motion.sampleRate)
            }
            ToolbarItem {
                RecordToolbarButton()
            }
        }
    }

    private var detail: some View {
        Group {
            switch model.screen {
            case .sensors: SensorsView()
            case .train: TrainView()
            case .decode: DecodeView()
            }
        }
    }

    private var screenSelection: Binding<AppModel.Screen?> {
        Binding(get: { model.screen }, set: { if let screen = $0 { model.screen = screen } })
    }
}

private struct RecordToolbarButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let recorder = model.recorder
        Button {
            recorder.isRecording ? recorder.stop() : recorder.start(audio: model.audio)
        } label: {
            Label(recorder.isRecording ? "Stop Recording" : "Record Session",
                  systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
        }
        .tint(recorder.isRecording ? .red : nil)
        .help("Record synchronized motion CSV + audio to ~/Documents/Subvox/Sessions")
    }
}
