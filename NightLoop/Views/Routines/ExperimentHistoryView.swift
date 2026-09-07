import SwiftData
import SwiftUI

struct ExperimentHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExperimentArchiveRecord.endDate, order: .reverse)
    private var records: [ExperimentArchiveRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Experiment History").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if records.isEmpty {
                ContentUnavailableView("No Archived Experiments", systemImage: "archivebox", description: Text("Archived experiments will rest here."))
            } else {
                List(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.name).font(.headline)
                            Spacer()
                            Text("Experiment \(record.sourceSlot - 4)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(record.totalActiveDays) active day\(record.totalActiveDays == 1 ? "" : "s")")
                        Text("\(record.startDate.formatted(date: .abbreviated, time: .omitted)) – \(record.endDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 470, minHeight: 430)
    }
}
