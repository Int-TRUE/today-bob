import SwiftUI
import UIKit
import WidgetKit

private let apiBaseURL = "https://today-bob-server.vercel.app"

struct MealWidgetEntry: TimelineEntry {
    let date: Date
    let mealLabel: String
    let menuItems: [String]
    let operatingHoursLabel: String
}

struct MealWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MealWidgetEntry {
        MealWidgetEntry(
            date: Date(),
            mealLabel: "아침",
            menuItems: ["길거리토스트", "우유", "샐러드"],
            operatingHoursLabel: "07:00~09:00"
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (MealWidgetEntry) -> Void
    ) {
        completion(placeholder(in: context))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<MealWidgetEntry>) -> Void
    ) {
        Task {
            let entry = await fetchCurrentMeal() ?? MealWidgetEntry(
                date: Date(),
                mealLabel: "오늘",
                menuItems: ["등록된 식단이 없어요"],
                operatingHoursLabel: ""
            )
            let nextRefresh = Calendar.current.date(
                byAdding: .minute,
                value: 30,
                to: Date()
            ) ?? Date().addingTimeInterval(1800)

            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func fetchCurrentMeal() async -> MealWidgetEntry? {
        var components = URLComponents(string: "\(apiBaseURL)/api/home")
        components?.queryItems = [
            URLQueryItem(name: "date", value: koreanDateString()),
            URLQueryItem(name: "at", value: ISO8601DateFormatter().string(from: Date()))
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(HomeResponse.self, from: data)
            return MealWidgetEntry(
                date: Date(),
                mealLabel: response.menu.label,
                menuItems: response.menu.items,
                operatingHoursLabel: response.operatingHours.label.replacingOccurrences(of: " ", with: "")
            )
        } catch {
            return nil
        }
    }

    private func koreanDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

struct HomeResponse: Decodable {
    let menu: MenuResponse
    let operatingHours: OperatingHoursResponse
}

struct MenuResponse: Decodable {
    let label: String
    let items: [String]
}

struct OperatingHoursResponse: Decodable {
    let label: String
}

struct TodayBobWidgetEntryView: View {
    let entry: MealWidgetEntry

    var body: some View {
        VStack(spacing: 0) {
            TomatoWidgetImage()

            Spacer(minLength: 5)

            VStack(spacing: 3) {
                ForEach(displayItems, id: \.self) { item in
                    Text(item)
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer(minLength: 5)

            Text(entry.operatingHoursLabel)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(entry.operatingHoursLabel.isEmpty ? 0 : 1)
        }
        .padding(.top, 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .background(Color.white)
        .containerBackground(.white, for: .widget)
    }

    private var displayItems: [String] {
        if entry.menuItems.isEmpty {
            return ["등록된 식단이 없어요"]
        }

        return Array(entry.menuItems.prefix(6))
    }

    private var fontSize: CGFloat {
        displayItems.count >= 5 ? 14 : 17
    }
}

private struct TomatoWidgetImage: View {
    var body: some View {
        Group {
            if let image = Self.bundleImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(Color(red: 1, green: 0.3, blue: 0.24))
                    .overlay(
                        Text("토")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 25, height: 27)
        .shadow(color: .black.opacity(0.1), radius: 1.5, x: 0, y: 1)
        .accessibilityHidden(true)
    }

    private static var bundleImage: UIImage? {
        guard let url = Bundle.main.url(forResource: "tomato_gold", withExtension: "png") else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }
}

@main
struct TodayBobWidget: Widget {
    let kind = "TodayBobWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MealWidgetProvider()) { entry in
            TodayBobWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("오늘밥뭐야")
        .description("현재 시간에 맞는 식단 메뉴를 보여줍니다.")
        .supportedFamilies([.systemSmall])
    }
}
