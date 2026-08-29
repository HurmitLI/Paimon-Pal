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
                    .frame(width: 144, height: 192)
                    .offset(y: -4)
                    .accessibilityLabel(accessibilityLabel)
            }
        }
        .frame(width: 180, height: 188)
        .clipped()
        .allowsHitTesting(false)
    }

    private var accessibilityLabel: String {
        switch pet.stage {
        case .sleeping: "宠物正在刘海中睡觉"
        case .waking: "宠物正在醒来"
        case .emerging: "宠物正在飞出刘海"
        case .idle: "宠物正在刘海旁待机"
        case .returning: "宠物正在返回刘海"
        }
    }
}
