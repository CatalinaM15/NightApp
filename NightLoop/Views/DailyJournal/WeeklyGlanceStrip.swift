import SwiftUI

struct WeeklyGlanceStrip: View {
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.self) { date in
                VStack(spacing: 5) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption)
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(.body, design: .rounded, weight: isToday(date) ? .bold : .regular))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isToday(date) ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isToday(date) ? .isSelected : [])
            }
        }
    }

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }
}
