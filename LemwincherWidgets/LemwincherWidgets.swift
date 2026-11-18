import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LemwincherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CookingTimerLiveActivity()
    }
}

/// Vert Lemwincher, version lumineuse (la Dynamic Island et l'activité sur l'écran verrouillé sont sur fond noir).
private let brand = Color(red: 0.204, green: 0.78, blue: 0.482)

/// Minuteur de cuisine : écran verrouillé + Dynamic Island (iPhone 15).
struct CookingTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingTimerAttributes.self) { context in
            LockScreenTimerView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.78))
                .activitySystemActionForegroundColor(brand)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji)
                        .font(.system(size: 34))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state, finished: context.isStale)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(brand)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.recipeName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !context.isStale {
                            ProgressView(timerInterval: context.state.start...context.state.end, countsDown: true) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(brand)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(brand)
            } compactTrailing: {
                CountdownText(state: context.state, finished: context.isStale)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(brand)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.isStale ? "checkmark" : "timer")
                    .foregroundStyle(brand)
            }
            .keylineTint(brand)
        }
    }
}

/// Compte à rebours qui s'actualise tout seul ; « Prêt ! » une fois terminé.
private struct CountdownText: View {
    let state: CookingTimerAttributes.ContentState
    let finished: Bool

    var body: some View {
        if finished || state.end <= Date() {
            Text("Prêt !")
        } else {
            Text(timerInterval: state.start...state.end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LockScreenTimerView: View {
    let context: ActivityViewContext<CookingTimerAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Text(context.attributes.emoji)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(brand.opacity(0.25), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.recipeName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(context.isStale ? "Minuteur terminé" : context.state.label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            CountdownText(state: context.state, finished: context.isStale)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(brand)
        }
        .padding(16)
    }
}
