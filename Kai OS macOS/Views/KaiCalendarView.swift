//
//  KaiCalendarView.swift
//  Kai OS macOS
//
//  Modern calendar view — today cards, upcoming list
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

struct KaiCalendarView: View {
    @EnvironmentObject var appState: AppState
    
    private var todayEvents: [CalendarEvent] {
        appState.calendarEvents.filter { Calendar.current.isDateInToday($0.date) }
    }
    
    private var upcomingEvents: [CalendarEvent] {
        appState.calendarEvents.filter { $0.date > Date() && !Calendar.current.isDateInToday($0.date) }
    }
    
    var body: some View {
        Group {
            if appState.calendarConnected || appState.outlookConnected {
                VStack(spacing: 0) {
                    // ── Header ──
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today").font(KaiFont.title3)
                            Text("\(todayEvents.count) events").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textTertiary)
                        }
                        
                        Spacer()
                        
                        Button("Refresh") {
                            appState.refreshCalendar()
                        }
                        .buttonBorderShape(.roundedRectangle)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, KaiSpacing.regular)
                    .padding(.vertical, 12)
                    
                    // ── Error Banner ──
                    KaiSourceErrorBanner(state: appState.calendarState)
                        .padding(.horizontal, KaiSpacing.regular)
                    
                    Divider().kaiDivider()
                    
                    // ── Today Events ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today").font(KaiFont.captionStrong)
                            .foregroundStyle(KaiColor.textTertiary)
                            .padding(.horizontal, KaiSpacing.regular)
                            .padding(.top, 8)
                        
                        if todayEvents.isEmpty {
                            Text("Nothing scheduled today").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textTertiary)
                                .padding(.horizontal, KaiSpacing.regular)
                                .padding(.vertical, 16)
                        }
                        
                        ForEach(todayEvents) { event in
                            calendarEventRow(event)
                        }
                        
                        Divider().kaiDivider()
                            .padding(.top, 4)
                        
                        Text("Next 14 Days").font(KaiFont.captionStrong)
                            .foregroundStyle(KaiColor.textTertiary)
                            .padding(.horizontal, KaiSpacing.regular)
                            .padding(.top, 8)
                        
                        if upcomingEvents.isEmpty {
                            Text("Nothing scheduled for the next 14 days").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textTertiary)
                                .padding(.horizontal, KaiSpacing.regular)
                                .padding(.vertical, 16)
                        }
                        
                        ForEach(upcomingEvents) { event in
                            calendarEventRow(event, isToday: false)
                        }
                    }
                }
            } else {
                KaiConnectCard(
                    title: "Calendar",
                    icon: "calendar",
                    explanation: "Kai OS reads your events from Apple Calendar. It can't change them, and nothing leaves this Mac.",
                    state: appState.calendarState,
                    connect: appState.connectCalendar
                )
            }
        }
        .onAppear {
            if appState.calendarConnected || appState.outlookConnected { appState.refreshCalendar() }
        }
    }
    
    // ── Event Row ──
    private func calendarEventRow(_ event: CalendarEvent, isToday: Bool = true) -> some View {
        HStack(spacing: 12) {
            // ── Color Bar ──
            RoundedRectangle(cornerRadius: 3)
                .fill(KaiColor.primary)
                .frame(width: 4, height: 48)
            
            // ── Content ──
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title).font(KaiFont.bodyStrong)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(KaiFont.caption2Strong)
                            .foregroundStyle(KaiColor.textTertiary)
                        Text(event.time).font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textSecondary)
                    }
                    
                    if !event.duration.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(KaiFont.caption2Strong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Text(event.duration).font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                        }
                    }
                    
                    if !event.location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(KaiFont.caption2Strong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Text(event.location).font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(KaiSpacing.regular)
        .background(
            RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                .fill(isToday ? KaiColor.primary.opacity(0.04) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                        .stroke(isToday ? KaiColor.primary.opacity(0.15) : Color.clear, lineWidth: 0.5)
                )
        )
    }
}
