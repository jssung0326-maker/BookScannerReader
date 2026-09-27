import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let items: [OnboardingItem] = [
        .init(
            icon: "camera.viewfinder",
            title: "책을 빠르게 스캔",
            detail: "한 페이지 또는 펼친 두 페이지를 촬영하고, 자동으로 분리·보정해 저장합니다."
        ),
        .init(
            icon: "rectangle.split.2x1",
            title: "책 크기를 일정하게",
            detail: "첫 페이지의 비율을 기준으로 삼아 이후 모든 페이지를 같은 규격으로 맞춥니다."
        ),
        .init(
            icon: "doc.text.magnifyingglass",
            title: "OCR · 검색 가능한 PDF",
            detail: "한국어/영어 OCR을 실행하고, 검색과 복사가 가능한 PDF를 만들어 관리합니다."
        ),
        .init(
            icon: "speaker.wave.2",
            title: "읽고, 찾고, 들어보세요",
            detail: "PDF Reader, 본문 검색, 북마크·메모, 음성 읽기를 한 앱에서 사용할 수 있습니다."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 26) {
                        Spacer()

                        Image(systemName: item.icon)
                            .font(.system(size: 72, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)

                        VStack(spacing: 12) {
                            Text(item.title)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)

                            Text(item.detail)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 32)

                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < items.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page == items.count - 1 ? "시작하기" : "다음")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

private struct OnboardingItem {
    let icon: String
    let title: String
    let detail: String
}
