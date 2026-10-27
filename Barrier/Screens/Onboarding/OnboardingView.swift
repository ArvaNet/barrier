import BarrierCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var template: Presets.Template?
    @State private var applied: Presets.Template?
    @State private var editing: StepTarget?
    @State private var adding: Slot?
    @State private var hasFollowUp = false
    @State private var followUp = Date().addingTimeInterval(42 * 86400)
    @State private var followUpWith = ""
    @State private var askingPermission = false

    private let pages = 7

    var body: some View {
        VStack(spacing: 0) {
            if page > 0 {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        // The glyph sits on the 16 pt line; the target stays 44 pt.
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44, alignment: .leading)
                    }
                    .accessibilityLabel("Back")
                    ProgressView(value: Double(page), total: Double(pages - 1)).tint(Palette.ink)
                        .frame(maxWidth: 200)
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, Metrics.margin)
                .foregroundStyle(Palette.ink)
            }
            Group {
                switch page {
                case 0: welcome
                case 1: templates
                case 2: slotPage(.pm)
                case 3: slotPage(.am)
                case 4: slotPage(.body)
                case 5: details
                default: reminders
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .background(Palette.bg.ignoresSafeArea())
        .sheet(item: $editing) { t in StepEditorSheet(target: t).barrier(model) }
        .sheet(item: $adding) { s in AddProductSheet(slot: s).barrier(model) }
        .onAppear {
            // Screenshot hook: `-fresh -screen onboarding-3` opens that page, as if "Starting a retinoid" was picked.
            guard let s = model.launch.screen, s.hasPrefix("onboarding-"), let n = Int(s.dropFirst("onboarding-".count)) else { return }
            if n >= 2 {
                template = .retinoid
                model.update { $0 = Presets.apply(.retinoid, to: $0, today: model.today) }
                applied = .retinoid
            } else if n == 1 {
                template = .retinoid
            }
            page = min(max(0, n), pages - 1)
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            WelcomeOrbit(size: 180)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Palette.stage, in: RoundedRectangle(cornerRadius: Metrics.stageRadius, style: .continuous))
            .padding(.bottom, 32)
            Text("Your dermatologist’s routine, remembered.")
                .font(.barrierLargeTitle).tracking(-0.5)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tendwell tells you exactly what to do tonight, reminds you at the right time, and adjusts when life gets in the way.")
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
        .padding(.horizontal, Metrics.margin)
        .padding(.vertical, 16)
    }

    /// A page title on the 16 pt line, above the list (never inside a row, where corners clip it).
    private func pageHeader(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.barrierLargeTitle).tracking(-0.5).foregroundStyle(Palette.ink)
            Text(text).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// The page's main button, floating over the list so rows scroll under it.
    private func bottomButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(disabled)
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 12)
            .padding(.bottom, 8)
            // Content fades out above the button instead of stopping at a hard line.
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Palette.bg.opacity(0), Palette.bg], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                    Palette.bg
                }
                .padding(.top, -28)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
    }

    private var templates: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                pageHeader("Where are you starting?", "Pick the closest one. You’ll fine-tune every step next.")
                    .padding(.horizontal, -Metrics.margin)
                    .padding(.bottom, 4)
                ForEach(Presets.Template.allCases) { t in
                    let on = template == t
                    Button {
                        template = t
                        Haptics.tap(model.state.settings.haptics)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: icon(t)).font(.title3).foregroundStyle(Palette.ink2).frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.title).font(.headline).foregroundStyle(Palette.ink)
                                Text(t.subtitle).font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(on ? Palette.ink : Palette.line2)
                        }
                        .padding(Metrics.cardPadding)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(on ? Palette.ink : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                if template == .cycling {
                    NoteBox(title: Guidance.skinCycling.title, text: Guidance.skinCycling.body, sources: Guidance.skinCycling.sources, symbol: "info.circle", onDismiss: nil)
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            bottomButton("Continue", disabled: template == nil) {
                if let t = template, t != applied {
                    model.update { $0 = Presets.apply(t, to: $0, today: model.today) }
                    applied = t
                }
                next()
            }
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

    private func pageTitle(_ slot: Slot) -> String {
        switch slot {
        case .pm: return "Your evening"
        case .am: return "Your morning"
        case .body, .body2: return "Back or body?"
        }
    }

    private func pageText(_ slot: Slot) -> String {
        switch slot {
        case .pm: return "Add what you use at night, in order. Tap one for how often or to start it slowly."
        case .am: return "Same for the morning. Sunscreen usually goes last."
        case .body, .body2: return "Got something for your back, chest or body too, like a lotion after the shower? Turn this on and it gets its own reminder and log. Otherwise, skip."
        }
    }

    private func slotPage(_ slot: Slot) -> some View {
        List {
            Group {
                SlotEditorSections(slot: slot, editing: $editing, adding: $adding)
            }
            .rows()
        }
        .barrierList()
        .contentMargins(.top, 4, for: .scrollContent)
        .safeAreaInset(edge: .top, spacing: 0) {
            pageHeader(pageTitle(slot), pageText(slot)).background(Palette.bg)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomButton(model.state.plan[slot].steps.isEmpty ? "Skip for now" : "Continue") { next() }
        }
    }

    private var details: some View {
        Form {
            Group {
                Section {
                    Toggle("I have a follow-up booked", isOn: $hasFollowUp)
                    if hasFollowUp {
                        DatePicker("Date", selection: $followUp, in: Date()..., displayedComponents: .date)
                        TextField("Dermatologist’s name (optional)", text: $followUpWith)
                    }
                } footer: {
                    Text("Tendwell reminds you the evening before and has a report ready.")
                }
                Section {
                    TextField("What your dermatologist said, e.g. skip tretinoin for 2 nights", text: Binding(
                        get: { model.state.plan.ifIrritated ?? "" },
                        set: { v in model.update { $0.plan.ifIrritated = v.isEmpty ? nil : v } }
                    ), axis: .vertical)
                    .lineLimit(2...5)
                } header: {
                    Text("If your skin gets irritated")
                } footer: {
                    Text("Shown whenever you log red or stinging skin.")
                }
            }
            .rows()
        }
        .barrierList()
        .contentMargins(.top, 4, for: .scrollContent)
        .safeAreaInset(edge: .top, spacing: 0) {
            pageHeader("A few details", "All optional. They make the reminders and your report smarter.").background(Palette.bg)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomButton("Continue") {
                if hasFollowUp {
                    let fu = FollowUp(day: Day(date: followUp), with: followUpWith.trimmingCharacters(in: .whitespaces).nilIfEmpty)
                    model.update { $0.plan.followUp = fu }
                }
                next()
            }
        }
    }

    private var reminders: some View {
        let s = model.state
        let pm = s.plan.pm
        let am = s.plan.am
        return VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .foregroundStyle(Palette.ink2)
                .padding(.top, 24)
                .padding(.bottom, 20)
            Text("Let Tendwell remind you").font(.barrierLargeTitle).tracking(-0.5).foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 14) {
                if pm.enabled && !pm.steps.isEmpty {
                    bullet("moon.stars", "Evenings at \(pm.time.formatted), with tonight’s exact steps.")
                }
                if am.enabled && !am.steps.isEmpty {
                    bullet("sun.max", "Mornings at \(am.time.formatted).")
                }
                ForEach(s.plan.activeSlots.filter(\.isBody), id: \.self) { slot in
                    let b = s.plan[slot]
                    bullet("drop.halffull", "\(b.displayName): \((b.cue ?? "daily").lowercased()), around \(b.time.formatted).")
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
                .buttonStyle(TertiaryButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 8)
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
