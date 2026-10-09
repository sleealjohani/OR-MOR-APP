import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    var onReplayIntro: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(settings.t("اللغة", "Language")) {
                    Picker(settings.t("لغة التطبيق", "App language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle(settings.t("تقليل الحركة", "Reduce motion"), isOn: $settings.reduceMotionOverride)
                    Toggle(settings.t("تخطي المقدمة تلقائيًا", "Skip the intro automatically"), isOn: $settings.autoSkipIntro)
                        .disabled(!settings.hasSeenIntro)
                    Picker(settings.t("جودة الرسوميات", "Graphics quality"), selection: $settings.graphicsQuality) {
                        Text(settings.t("عالية", "High")).tag(GraphicsQuality.high)
                        Text(settings.t("متوازنة (توفير البطارية)", "Balanced (saves battery)")).tag(GraphicsQuality.balanced)
                    }
                    Button(settings.t("إعادة تشغيل المقدمة", "Replay the intro"), action: onReplayIntro)
                } header: {
                    Text(settings.t("التجربة", "Experience"))
                } footer: {
                    Text(settings.t("يتبع «تقليل الحركة» أيضًا إعداد إمكانية الوصول في النظام.",
                                    "Reduce motion also follows the system accessibility setting."))
                }
                Section {
                    LabeledContent(settings.t("الإصدار", "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                } footer: {
                    Text(settings.t("نموذج أولي: البيانات والحجوزات تجريبية وغير مرتبطة بالمقهى بعد.",
                                    "Prototype: data and bookings are simulated and not yet connected to the café."))
                }
            }
            .tint(Brand.gold)
            .navigationTitle(settings.t("الإعدادات", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("تم", "Done")) { dismiss() }
                }
            }
        }
    }
}
