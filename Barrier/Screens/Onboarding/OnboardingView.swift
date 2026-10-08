import BarrierCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var template: Presets.Template?
    @State private var editing: StepTarget?
    @State private var adding: Slot?
    @State private var hasFollowUp = false
    @State private var followUp = Date().addingTimeInterval(42 * 86400)
    @State private var followUpWith = ""
    @State private var askingPermission = false

    private let pages = 6

    var body: some View {
        VStack(spacing: 0) {
            if page > 0 {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                    ProgressView(value: Double(page), total: Double(pages - 1)).tint(Palette.accent)
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)
                .foregroundStyle(Palette.ink)
            }
            Group {
                switch page {
                case 0: welcome
                case 1: templates
                case 2: slotPage(.pm)
                case 3: slotPage(.am)
                case 4: details
                default: reminders
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .background(Palette.bg.ignoresSafeArea())
        .sheet(item: $editing) { t in StepEditorSheet(target: t).environment(model) }
        .sheet(item: $adding) { s in AddProductSheet(slot: s).environment(model) }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            OrbitView(
                nodes: [OrbitNode(hue: .gold, state: .current), OrbitNode(hue: .clay, state: .future), OrbitNode(hue: .sage, state: .future), OrbitNode(hue: .mist, state: .future)],
                current: 0, size: 150, showCount: false
            )
            .environment(\.colorScheme, .dark)
            .padding(28)
            .background(Palette.stage, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.bottom, 36)
            Text("Your dermatologist’s routine, remembered.")
                .font(Typeface.display(38, weight: 420))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Barrier tells you exactly what to do tonight, reminds you at the right time, and adjusts when life gets in the way.")
                .font(.body)
                .foregroundStyle(Palette.ink2)
                .padding(.top, 14)
            Spacer()
            Button("Set up my routine") { next() }
                .buttonStyle(PrimaryButtonStyle())
            Text("Everything stays on your iPhone.")
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(24)
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where are you starting?").font(.barrierTitle).foregroundStyle(Palette.ink)
                    Text("Pick the closest one. You’ll fine-tune every step next.").font(.subheadline).foregroundStyle(Palette.ink2)
                        .padding(.bottom, 8)
                    ForEach(Presets.Template.allCases) { t in
                        Button {
                            template = t
                            Haptics.tap(model.state.settings.haptics)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: icon(t)).font(.title3).foregroundStyle(Palette.accent).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.title).font(.headline).foregroundStyle(Palette.ink)
                                    Text(t.subtitle).font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: template == t ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(template == t ? Palette.accent : Palette.line2)
                            }
                            .padding(16)
                            .background(template == t ? Palette.accentSoft : Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(template == t ? Palette.accent : Palette.line, lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)
                    }
                    if template == .cycling {
                        NoteBox(title: Guidance.skinCycling.title, text: Guidance.skinCycling.body, sources: Guidance.skinCycling.sources, symbol: "info.circle", onDismiss: nil)
                    }
                }
                .padding(24)
            }
            Button("Continue") {
                if let t = template {
                    model.update { $0 = Presets.apply(t, to: $0, today: model.today) }
                }
                next()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(template == nil)
            .padding(24)
        }
    }

    private func icon(_ t: Presets.Template) -> String {
        switch t {
        case .derm: return "stethoscope"
        case .retinoid: return "moon.stars"
        case .simple: return "drop"
        case .cycling: return "circle.circle"
        }
    }

    private func slotPage(_ slot: Slot) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(slot == .pm ? "Your evening" : "Your morning").font(.barrierTitle).foregroundStyle(Palette.ink)
                        Text(slot == .pm
                             ? "Add what you use at night, in order. Tap a step to set how often, the amount, and your dermatologist’s exact words."
                             : "Same for the morning. Sunscreen usually goes last.")
                            .font(.subheadline).foregroundStyle(Palette.ink2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
                SlotEditorSections(slot: slot, editing: $editing, adding: $adding)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            Button(model.state.plan[slot].steps.isEmpty ? "Skip for now" : "Continue") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(24)
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A few details").font(.barrierTitle).foregroundStyle(Palette.ink)
                        Text("All optional. They make the reminders and your report smarter.").font(.subheadline).foregroundStyle(Palette.ink2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
                Section {
                    Toggle("I have a follow-up booked", isOn: $hasFollowUp)
                    if hasFollowUp {
                        DatePicker("Date", selection: $followUp, in: Date()..., displayedComponents: .date)
                        TextField("With (e.g. Dr. Petrauskienė)", text: $followUpWith)
                    }
                } footer: {
                    Text("Barrier reminds you the evening before and has a report ready.")
                }
                Section {
                    TextField("e.g. skip tretinoin for 2 nights, moisturizer only", text: Binding(
                        get: { model.state.plan.ifIrritated ?? "" },
                        set: { v in model.update { $0.plan.ifIrritated = v.isEmpty ? nil : v } }
                    ), axis: .vertical)
                    .lineLimit(2...5)
                } header: {
                    Text("If your skin gets irritated, your dermatologist said…")
                } footer: {
                    Text("Shown whenever you log red or stinging skin.")
                }
            }
            .scrollContentBackground(.hidden)
            Button("Continue") {
                if hasFollowUp {
                    let fu = FollowUp(day: Day(date: followUp), with: followUpWith.trimmingCharacters(in: .whitespaces).nilIfEmpty)
                    model.update { $0.plan.followUp = fu }
                }
                next()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(24)
        }
    }

    private var reminders: some View {
        let s = model.state
        let pm = s.plan.pm
        let am = s.plan.am
        return VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 44))
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 24)
            Text("Let Barrier remind you").font(.barrierTitle).foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 14) {
                if pm.enabled && !pm.steps.isEmpty {
                    bullet("moon.stars", "Evenings at \(pm.time.formatted), with tonight’s exact steps.")
                }
                if am.enabled && !am.steps.isEmpty {
                    bullet("sun.max", "Mornings at \(am.time.formatted).")
                }
                bullet("hand.tap", "Long-press a reminder: Done, In 30 minutes, or Not tonight.")
                bullet("checkmark.seal", "Once it’s done, the nudges stop.")
            }
            .padding(.top, 20)
            Spacer()
            Button(askingPermission ? "One moment…" : "Turn on reminders") {
                askingPermission = true
                Task {
                    await NotificationService.shared.requestAuthorization()
                    await model.refreshNotificationStatus()
                    finish()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(askingPermission)
            Button("Not now") { finish() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 6)
        }
        .padding(24)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.body).foregroundStyle(Palette.ink2).frame(width: 24)
            Text(text).font(.body).foregroundStyle(Palette.ink)
        }
    }

    private func next() {
        withAnimation(.easeOut(duration: 0.3)) { page = min(page + 1, pages - 1) }
    }

    private func finish() {
        var s = model.state
        s.plan.createdAt = min(s.plan.createdAt, model.today)
        model.finishOnboarding(s)
        model.scheduleNotifications(immediately: true)
        let tonight = model.instance(.pm)
        model.show(tonight.steps.isEmpty ? "You’re set." : "You’re set. Tonight is \(tonight.label.lowercased()).")
    }
}
