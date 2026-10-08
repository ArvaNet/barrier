// Wire types shared by the app and the Worker.

export type ReminderKind = 'main' | 'nudge' | 'followup' | 'spf' | 'timer' | 'snooze';

export interface ReminderIn {
  /** Stable per device, e.g. "2026-10-09:pm:main". */
  id: string;
  fireAt: number; // epoch ms
  kind: ReminderKind;
  slot?: 'am' | 'pm';
  date?: string;
  title: string;
  body: string;
  url: string;
  /** Sent instead when an earlier reminder for this slot went unanswered. */
  genericTitle?: string;
  genericBody?: string;
}

export interface PushPayload {
  title: string;
  body: string;
  url: string;
  tag: string;
  kind: ReminderKind;
  slot?: 'am' | 'pm';
  date?: string;
  reminderId: string;
}

export interface RegisterRequest {
  subscription: { endpoint: string; keys: { p256dh: string; auth: string } };
  tz: string;
  deviceId?: string;
  token?: string;
}

export interface RegisterResponse {
  deviceId: string;
  token: string;
}

export interface ScheduleRequest {
  reminders: ReminderIn[];
}

export const MAX_REMINDERS = 200;
