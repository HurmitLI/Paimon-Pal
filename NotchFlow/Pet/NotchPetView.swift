import SwiftUI

struct NotchPetView: View {
    @ObservedObject var pet: NotchPetController

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if pet.stage != .sleeping, let image = pet.currentImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    // 各套序列帧的原始画布比例不同，必须等比例缩放。
                    // 强行拉伸会在“出场 → 待机”切换时产生一帧跳缩。
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 144, height: 192, alignment: .top)
                    .offset(y: verticalOffset)
                    .accessibilityLabel(accessibilityLabel)
            }
        }
        .frame(width: 180, height: 188)
        .clipped()
        .allowsHitTesting(false)
    }

    private var verticalOffset: CGFloat {
        // 这几套生成素材的角色在画布中所处高度不同。
        // 分状态校准头饰基线，使它始终低于本机 32pt 的真实刘海安全线。
        switch pet.stage {
        case .sleeping:
            8
        case .waking:
            8
        case .emerging:
            18
        case .idle:
            8
        case .reacting:
            22
        case .listening:
            14
        case .returning:
            18
        }
    }

    private var accessibilityLabel: String {
        switch pet.stage {
        case .sleeping: "宠物正在刘海中睡觉"
        case .waking: "宠物正在醒来"
        case .emerging: "宠物正在飞出刘海"
        case .idle: "宠物正在刘海旁待机"
        case .reacting: "宠物正在回应点击"
        case .listening: "宠物正在聆听"
        case .returning: "宠物正在返回刘海"
        }
    }
}
