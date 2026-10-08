// Core data model. Everything here is plain JSON so the whole state can be
// saved as one object and exported as a backup.

export type ISODate = string; // local calendar date, 'YYYY-MM-DD'
export type Slot = 'am' | 'pm';

export type ProductKind =
  | 'cleanser'
  | 'retinoid'
  | 'exfoliant'
  | 'treatment'
  | 'serum'
  | 'moisturizer'
  | 'spf'
  | 'oral'
  | 'other';

export interface Product {
  id: string;
  name: string;
  kind: ProductKind;
  /** Dermatologist's instruction for this product, in their words. */
  note?: string;
  /** First day you use it. Steps for it are not due before this. */
  from?: ISODate;
  /** Last day of the course (e.g. a 12-week antibiotic). */
  until?: ISODate;
  barcode?: string;
  brand?: string;
}

/** Which instances of a slot a step belongs to. */
export type StepOn =
  | { type: 'all' }
  | { type: 'nights'; nights: number[] } // positions in the base rotation
  | { type: 'weekdays'; days: number[] }; // 0 = Sunday … 6 = Saturday

export interface Step {
  id: string;
  productId: string;
  amount?: string;
  how?: string;
  /** Minutes to wait after this step before the next one. */
  waitMin?: number;
  on: StepOn;
}

export interface EaseInPhase {
  days: number;
  /** Extra recovery nights appended to the rotation during this phase. */
  extraRest: number;
}

export interface SlotPlan {
  enabled: boolean;
  time: string; // 'HH:MM'
  /** Base rotation length (1 = same every time, 4 = skin cycling). */
  length: number;
  steps: Step[];
  /** Optional custom names per base rotation position. */
  names?: Record<number, string>;
  easeIn?: { start: ISODate; phases: EaseInPhase[] };
  /** Replay of history starts here: on `date`, the rotation is at `pos`. */
  anchor: { date: ISODate; pos: number };
}

export interface Plan {
  am: SlotPlan;
  pm: SlotPlan;
  followUp?: { date: ISODate; with?: string };
  /** What the dermatologist said to do if skin gets irritated. */
  ifIrritated?: string;
  dermNotes?: string;
  createdAt: ISODate;
}

/** open = nothing logged yet (e.g. a recovery night chosen but not done). */
export type EntryStatus = 'done' | 'skipped' | 'open';

export interface Entry {
  date: ISODate;
  slot: Slot;
  status: EntryStatus;
  /** Turned into a recovery night (irritation): actives dropped, rotation holds. */
  recovery?: boolean;
  /** Rotation position this entry resolved (for done/skipped). */
  pos?: number;
  /** Snapshot of the night, so history still reads right after plan edits. */
  label?: string;
  hue?: Hue;
  steps?: string[]; // step ids ticked, for partial routines
  at: number;
}

export type Feeling = 'calm' | 'dry' | 'tight' | 'red' | 'stinging' | 'breakout' | 'flaky';

export interface CheckIn {
  date: ISODate;
  feel: Feeling[];
  note?: string;
  at: number;
}

export interface Pause {
  id: string;
  from: ISODate;
  to: ISODate; // inclusive
  reason: 'travel' | 'irritation' | 'procedure' | 'sick' | 'other';
}

export interface PhotoMeta {
  id: string;
  date: ISODate;
  at: number;
  note?: string;
  w: number;
  h: number;
}

export interface Question {
  id: string;
  text: string;
  at: number;
  answered?: boolean;
}

export type Hue = 'gold' | 'clay' | 'sage' | 'mist' | 'rose' | 'lilac' | 'dawn';

export interface Settings {
  theme: 'auto' | 'day' | 'dusk';
  nudge: boolean;
  nudgeAfterMin: number;
  spfMidday: boolean;
  spfTime: string;
  photoDay: number; // weekday 0–6, -1 = off
  uv?: { lat: number; lon: number; place?: string };
  sound: boolean;
}

export interface PushState {
  deviceId: string;
  token: string;
  enabled: boolean;
  lastSync?: number;
}

export interface AppState {
  version: 1;
  onboarded: boolean;
  plan: Plan;
  products: Product[];
  log: Entry[];
  checkins: CheckIn[];
  pauses: Pause[];
  photos: PhotoMeta[];
  questions: Question[];
  settings: Settings;
  push?: PushState;
  dismissed: string[]; // one-off cards and conflict notes the user hid
  milestonesSeen: string[];
}
