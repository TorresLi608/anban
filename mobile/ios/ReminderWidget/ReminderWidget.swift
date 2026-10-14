import WidgetKit
import SwiftUI

// MARK: - 数据模型
struct ReminderItem: Decodable, Identifiable {
    var id: String { "\(channel)_\(at)" }
    let label: String
    let channel: String
    let at: Int64
    let due: Int64?
    
    var atDate: Date {
        Date(timeIntervalSince1970: TimeInterval(at) / 1000.0)
    }
    
    var dueDate: Date? {
        guard let due = due else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(due) / 1000.0)
    }
}

struct ReminderEntry: TimelineEntry {
    let date: Date
    let activeItem: ReminderItem?
    let upcomingItems: [ReminderItem]
    let syncedTime: String
    let isConfigured: Bool
}

// MARK: - TimelineProvider
struct ReminderTimelineProvider: TimelineProvider {
    private let appGroupId = "group.app.anban.anban"
    
    func placeholder(in context: Context) -> ReminderEntry {
        ReminderEntry(
            date: Date(),
            activeItem: ReminderItem(label: "下次化疗", channel: "chemo", at: Int64(Date().addingTimeInterval(3600 * 24).timeIntervalSince1970 * 1000), due: Int64(Date().addingTimeInterval(3600 * 25).timeIntervalSince1970 * 1000)),
            upcomingItems: [
                ReminderItem(label: "PICC 冲管", channel: "picc", at: Int64(Date().addingTimeInterval(3600 * 48).timeIntervalSince1970 * 1000), due: nil)
            ],
            syncedTime: "今日同步",
            isConfigured: true
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ReminderEntry) -> Void) {
        completion(loadCurrentEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminderEntry>) -> Void) {
        let entry = loadCurrentEntry()
        // 下次刷新时间：最近的一个提醒时间，或 15 分钟后
        var nextUpdate = Date().addingTimeInterval(15 * 60)
        if let nextAt = entry.activeItem?.atDate, nextAt > Date() {
            nextUpdate = min(nextUpdate, nextAt)
        }
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentEntry() -> ReminderEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let synced = defaults?.string(forKey: "reminder_synced") ?? ""
        guard let jsonString = defaults?.string(forKey: "reminder_plan"),
              let data = jsonString.data(using: .utf8) else {
            return ReminderEntry(date: Date(), activeItem: nil, upcomingItems: [], syncedTime: synced, isConfigured: false)
        }
        
        do {
            let decoder = JSONDecoder()
            let allItems = try decoder.decode([ReminderItem].self, from: data)
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let futureItems = allItems.filter { $0.at >= nowMs - 60 * 1000 }.sorted { $0.at < $1.at }
            
            let active = futureItems.first
            let upcoming = Array(futureItems.dropFirst().prefix(3))
            
            return ReminderEntry(
                date: Date(),
                activeItem: active,
                upcomingItems: upcoming,
                syncedTime: synced,
                isConfigured: true
            )
        } catch {
            return ReminderEntry(date: Date(), activeItem: nil, upcomingItems: [], syncedTime: synced, isConfigured: false)
        }
    }
}

// MARK: - 主视图与多尺寸自适应
extension View {
    @ViewBuilder
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOSApplicationExtension 17.0, iOS 17.0, *) {
            containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            background(backgroundView)
        }
    }
}

struct ReminderWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: ReminderEntry
    
    private let bgGradient = LinearGradient(
        colors: [Color(red: 23/255, green: 56/255, blue: 47/255), Color(red: 35/255, green: 85/255, blue: 70/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                MediumWidgetView(entry: entry)
            }
        }
        .widgetBackground(bgGradient)
        .widgetURL(URL(string: "anban://reminder"))
    }
}

// MARK: - 辅助格式化函数
private func formatClock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func formatDayHeadline(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return "今天"
    } else if calendar.isDateInTomorrow(date) {
        return "明天"
    } else {
        let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if diff > 0 {
            return "\(diff)天后"
        } else {
            return "即将到来"
        }
    }
}

// MARK: - 中尺寸视图 (4x2 黄金尺寸)
struct MediumWidgetView: View {
    var entry: ReminderEntry
    
    var body: some View {
        if let item = entry.activeItem {
            HStack(spacing: 12) {
                // 左侧主焦点区
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "cross.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 178/255, green: 227/255, blue: 213/255))
                        Text(item.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatDayHeadline(item.atDate))
                            .font(.system(size: 21, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text(formatClock(item.atDate))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 195/255, green: 236/255, blue: 224/255))
                    }
                    
                    // 双时间透出：提醒时间 vs 实际就诊/执行时间
                    HStack(spacing: 6) {
                        if let dueDate = item.dueDate {
                            Text("就诊 \(formatClock(dueDate))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.white.opacity(0.22))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        Text("闹钟 \(formatClock(item.atDate))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.80))
                    }
                    
                    Spacer(minLength: 0)
                    
                    Text("安伴 · 云端加密守护")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 中间轻量分割线
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                
                // 右侧待办排程列表
                VStack(alignment: .leading, spacing: 7) {
                    Text("后续行程")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(red: 180/255, green: 220/255, blue: 210/255))
                    
                    if entry.upcomingItems.isEmpty {
                        VStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16))
                                .foregroundColor(Color.white.opacity(0.4))
                            Text("暂无更多排程")
                                .font(.system(size: 10.5))
                                .foregroundColor(Color.white.opacity(0.6))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(entry.upcomingItems.prefix(2)) { up in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(up.label)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(formatClock(up.atDate))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(red: 195/255, green: 236/255, blue: 224/255))
                                }
                                if let due = up.dueDate {
                                    Text("就诊 \(formatClock(due))")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Color.white.opacity(0.70))
                                }
                            }
                            .padding(5)
                            .background(Color.black.opacity(0.12))
                            .cornerRadius(6)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        } else {
            // 空状态
            VStack(spacing: 8) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 26))
                    .foregroundColor(Color(red: 180/255, green: 228/255, blue: 215/255))
                Text(entry.isConfigured ? "今日作息照护已就绪" : "点此进入安伴开启提醒")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("把陪护的事，安心记好")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }
}

// MARK: - 小尺寸视图 (2x2)
struct SmallWidgetView: View {
    var entry: ReminderEntry
    
    var body: some View {
        if let item = entry.activeItem {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 178/255, green: 227/255, blue: 213/255))
                    Text(item.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                }
                
                Spacer(minLength: 0)
                
                Text(formatDayHeadline(item.atDate))
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                
                Text(formatClock(item.atDate))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 195/255, green: 236/255, blue: 224/255))
                
                if let due = item.dueDate {
                    Text("就诊 \(formatClock(due))")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.20))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                
                Spacer(minLength: 0)
                
                Text("安伴守护")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            .padding(10)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 180/255, green: 228/255, blue: 215/255))
                Text("安伴")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("一切安好")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
        }
    }
}

// MARK: - 大尺寸视图 (4x4)
struct LargeWidgetView: View {
    var entry: ReminderEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部导航区
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 178/255, green: 227/255, blue: 213/255))
                    Text("安伴 · 照护提醒日程")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Text(entry.syncedTime.isEmpty ? "已连接" : entry.syncedTime)
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            
            // 当前焦点卡片
            if let item = entry.activeItem {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("当前首要排程")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 180/255, green: 228/255, blue: 215/255))
                        Spacer()
                        if let due = item.dueDate {
                            Text("实际就诊：\(formatClock(due))")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.white.opacity(0.24))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.label)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(formatDayHeadline(item.atDate)) \(formatClock(item.atDate))")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 195/255, green: 236/255, blue: 224/255))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
            }
            
            // 后续列表
            Text("即将执行")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.white.opacity(0.85))
            
            if entry.upcomingItems.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 26))
                        .foregroundColor(Color.white.opacity(0.35))
                    Text("暂无后续排程，请按时休息")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.65))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(entry.upcomingItems.prefix(3)) { up in
                    HStack {
                        Text(up.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        if let due = up.dueDate {
                            Text("就诊 \(formatClock(due)) · ")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color.white.opacity(0.70))
                        }
                        Text(formatClock(up.atDate))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 195/255, green: 236/255, blue: 224/255))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.12))
                    .cornerRadius(8)
                }
            }
            
            Spacer(minLength: 0)
            
            // 底部安全声明
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.55))
                Text("所有照护与医疗数据均在本机与云端端到端加密保存")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .padding(14)
    }
}

// MARK: - Widget 定义
struct ReminderWidget: Widget {
    let kind: String = "ReminderWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReminderTimelineProvider()) { entry in
            ReminderWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("安伴 · 照护与就医提醒")
        .description("在桌面即刻掌握下一次化疗、PICC冲管、服药作息及实际就诊时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
