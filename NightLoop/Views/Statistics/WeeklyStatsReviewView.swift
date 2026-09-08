import SwiftData
import SwiftUI

struct WeeklyStatsReviewView: View {
    @Query(sort: \CardOption.sortOrder) private var options: [CardOption]
    @Query(sort: \SlotSelectionHistory.date) private var history: [SlotSelectionHistory]
    @Query(sort: \Routine.cardSlot) private var routines: [Routine]

    let date: Date
    let close: () -> Void

    private var stats: WeeklyStatsSnapshot {
        WeeklyStatsCalculator.calculate(on: date, options: options, history: history, routines: routines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEKLY REVIEW").font(JournalTypography.eyebrow).tracking(1.4).foregroundStyle(JournalPalette.ember)
                        Text("Today's Cards").font(JournalTypography.journalTitle)
                        Text("\(stats.weekStart.formatted(date: .abbreviated, time: .omitted)) – \(stats.weekEnd.formatted(date: .abbreviated, time: .omitted))")
                            .font(JournalTypography.date).foregroundStyle(JournalPalette.secondaryInk)
                    }
                    Spacer()
                    Button("Close", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(JournalPalette.raised)
                        .frame(width: 30, height: 30)
                        .background(JournalPalette.card, in: Circle())
                        .help("Close weekly stats")
                }

                statCard("Body Care", icon: "sparkles") {
                    ForEach(stats.bodyCare) { item in
                        statLine(item.optionName, value: item.daysSinceLastPicked.map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "Never")
                    }
                }
                statCard("Exercise", icon: "figure.run") {
                    ratio(stats.exerciseCompletedDays)
                }
                statCard("Hobby", icon: "paintbrush.pointed") {
                    Text(stats.hobbiesDone.isEmpty ? "No hobbies completed yet this week." : "This week you did: \(stats.hobbiesDone.joined(separator: ", ")).")
                }
                statCard("Daily Care", icon: "heart.text.square") {
                    ratio(stats.dailyCareCompletedDays)
                }
                statCard("Experiments", icon: "flask") {
                    if stats.experiments.isEmpty {
                        Text("No active experiments.").foregroundStyle(.secondary)
                    } else {
                        ForEach(stats.experiments) { experiment in
                            statLine(experiment.name, value: "\(experiment.completedDays)/7 · \(experiment.streakDays)-day streak")
                        }
                    }
                }
            }
            .padding(24)
        }
        .foregroundStyle(JournalPalette.ink)
        .background { LeatherJournalBackground() }
    }

    private func ratio(_ completed: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(completed)/7").font(.title2.weight(.semibold))
            ProgressView(value: Double(completed), total: 7).tint(JournalPalette.raised)
        }
    }

    private func statLine(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func statCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(JournalTypography.sectionTitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(JournalPalette.paperInk)
        .journalCard()
    }
}
