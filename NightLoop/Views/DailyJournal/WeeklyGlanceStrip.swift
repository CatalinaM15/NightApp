import SwiftUI

struct WeeklyGlanceStrip: View {
    let referenceDate: Date
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { date in
                VStack(spacing: 5) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isToday(date) ? JournalPalette.ember : JournalPalette.paperSecondaryInk)
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(.body, design: .rounded, weight: isToday(date) ? .bold : .regular))
                        .foregroundStyle(isToday(date) ? JournalPalette.ink : JournalPalette.paperInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isToday(date) ? JournalPalette.raised : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if isToday(date) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(JournalPalette.ember.opacity(0.55), lineWidth: 0.75)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityValue(isToday(date) ? "Today" : "")
                .accessibilityAddTraits(isToday(date) ? .isSelected : [])
            }
        }
        .padding(6)
        .background(JournalPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(JournalPalette.paperRule.opacity(0.65), lineWidth: 0.75)
        }
        .accessibilityLabel("This week")
    }

    private var days: [Date] {
        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: referenceDate)
    }
}
