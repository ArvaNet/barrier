import { CalendarDays, LayoutList, Stethoscope, Sun } from 'lucide-react';
import { useEffect, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { NavLink } from 'react-router-dom';
import { create } from 'zustand';
import type { Source } from '../lib/content';
import type { Hue } from '../lib/types';

export const hueVar = (h: Hue | undefined) => `var(--${h ?? 'sage'})`;

export function Sheet({ open, onClose, children, label }: { open: boolean; onClose: () => void; children: ReactNode; label: string }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    ref.current?.focus();
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  }, [open, onClose]);
  if (!open) return null;
  return createPortal(
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label={label} tabIndex={-1} ref={ref} onClick={(e) => e.stopPropagation()}>
        <div className="sheet-grip" />
        {children}
      </div>
    </div>,
    document.body,
  );
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: string }) {
  return <button type="button" role="switch" aria-checked={on} aria-label={label} className="toggle" onClick={() => onChange(!on)} />;
}

export function Seg<T extends string | number>({ value, options, onChange, label }: {
  value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; label: string;
}) {
  return (
    <div className="seg" role="group" aria-label={label}>
      {options.map((o) => (
        <button key={String(o.value)} type="button" aria-pressed={o.value === value} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Sources({ list }: { list: Source[] }) {
  if (!list.length) return null;
  return (
    <div className="sources">
      {list.map((s) => (
        <a key={s.url} href={s.url} target="_blank" rel="noreferrer">
          {s.label}
        </a>
      ))}
    </div>
  );
}

export function TabBar() {
  const tabs = [
    { to: '/', label: 'Today', icon: Sun, end: true },
    { to: '/plan', label: 'Routine', icon: LayoutList },
    { to: '/progress', label: 'Progress', icon: CalendarDays },
    { to: '/derm', label: 'Derm', icon: Stethoscope },
  ];
  return (
    <nav className="tabbar no-print" aria-label="Main">
      {tabs.map((t) => (
        <NavLink key={t.to} to={t.to} end={t.end} className={({ isActive }) => (isActive ? 'active' : '')}>
          <t.icon size={22} strokeWidth={1.8} />
          {t.label}
        </NavLink>
      ))}
    </nav>
  );
}

// ---------------------------------------------------------------------------
// Toasts with an optional action (Undo).

interface ToastState {
  msg: string | null;
  action?: { label: string; run: () => void };
  id: number;
  show: (msg: string, action?: { label: string; run: () => void }) => void;
  hide: () => void;
}

export const useToast = create<ToastState>((set, get) => ({
  msg: null,
  id: 0,
  show: (msg, action) => {
    const id = get().id + 1;
    set({ msg, action, id });
    setTimeout(() => {
      if (get().id === id) set({ msg: null, action: undefined });
    }, action ? 5000 : 2600);
  },
  hide: () => set({ msg: null, action: undefined }),
}));

export function Toaster() {
  const { msg, action, hide } = useToast();
  if (!msg) return null;
  return (
    <div className="toast no-print" role="status">
      <span>{msg}</span>
      {action && (
        <button
          type="button"
          onClick={() => {
            action.run();
            hide();
          }}
        >
          {action.label}
        </button>
      )}
    </div>
  );
}

export function haptic(ms = 12) {
  try {
    navigator.vibrate?.(ms);
  } catch {
    /* not supported */
  }
}
