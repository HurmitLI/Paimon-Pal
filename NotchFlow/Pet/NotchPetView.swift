import SwiftUI

struct NotchPetView: View {
    @ObservedObject var pet: NotchPetController
    @State private var displayedImage: NSImage?
    @State private var previousImage: NSImage?
    @State private var blendProgress = 1.0

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if pet.stage != .sleeping, let image = displayedImage ?? pet.currentImage {
                ZStack {
                    if let previousImage, blendProgress < 1 {
                        petImage(previousImage)
                            .opacity(1 - blendProgress)
                    }
                    petImage(image)
                        .opacity(blendProgress)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .frame(width: 180, height: 188)
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            displayedImage = pet.currentImage
        }
        .onChange(of: pet.frameSequence) { _, _ in
            let nextImage = pet.currentImage
            guard pet.frameTransitionDuration > 0, displayedImage != nil else {
                previousImage = nil
                displayedImage = nextImage
                blendProgress = 1
                return
            }

            previousImage = displayedImage
            displayedImage = nextImage
            blendProgress = 0
            withAnimation(.linear(duration: pet.frameTransitionDuration)) {
                blendProgress = 1
            }
        }
    }

    private func petImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            // 各套序列帧的原始画布比例不同，必须等比例缩放。
            // 强行拉伸会在“出场 → 待机”切换时产生一帧跳缩。
            .aspectRatio(contentMode: .fit)
            .frame(width: 144, height: 192, alignment: .top)
            .offset(y: verticalOffset)
    }

    private var verticalOffset: CGFloat {
        NotchPetPresentationMetrics.verticalOffset(for: pet.stage)
    }

    private var accessibilityLabel: String {
        switch pet.stage {
        case .sleeping: "宠物正在刘海中睡觉"
        case .waking: "宠物正在醒来"
        case .emerging: "宠物正在飞出刘海"
        case .idle: "宠物正在刘海旁待机"
        case .reacting: "宠物正在回应点击"
        case .listening: "宠物正在聆听"
        case .speaking: "宠物正在回答"
        case .celebrating: "宠物正在庆祝成功"
        case .returning: "宠物正在返回刘海"
        }
    }
}

enum NotchPetPresentationMetrics {
    static func verticalOffset(for stage: NotchPetStage) -> CGFloat {
        // 完整身体动作已经在素材加载层统一角色高度与脚底锚点，
        // 因此必须共用同一偏移，避免状态切换时再次人为跳位。
        switch stage {
        case .sleeping:
            8
        case .waking:
            8
        case .emerging:
            18
        case .idle:
            18
        case .reacting:
            18
        case .listening:
            18
        case .speaking:
            18
        case .celebrating:
            18
        case .returning:
            18
        }
    }
}
