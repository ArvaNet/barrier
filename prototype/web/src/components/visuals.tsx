import { useEffect, useId, useRef, useState } from 'react';
import type { Ring } from '../lib/engine';
import type { Hue } from '../lib/types';
import { hueVar } from './ui';

export interface OrbitNode {
  hue: Hue;
  state: 'done' | 'current' | 'future' | 'rest';
}

/**
 * The signature visual: the rotation as nodes on a ring, tonight at the top.
 * When tonight changes, the ring turns forward to bring the next night up.
 */
export function Orbit({ nodes, current, size = 120, label }: { nodes: OrbitNode[]; current: number; size?: number; label?: string }) {
  const n = Math.max(1, nodes.length);
  const step = 360 / n;
  const rot = useRef<{ index: number; deg: number }>({ index: current, deg: -current * step });
  if (current !== rot.current.index) {
    const delta = ((current - rot.current.index) % n + n) % n;
    rot.current = { index: current, deg: rot.current.deg - delta * step };
  }
  const id = useId().replace(/:/g, '');
  const c = 50;
  const R = 36;
  return (
    <svg className="orbit" width={size} height={size} viewBox="0 0 100 100" role="img" aria-label={label ?? `Night ${current + 1} of ${n}`}>
      <defs>
        <filter id={`glow-${id}`} x="-100%" y="-100%" width="300%" height="300%">
          <feGaussianBlur stdDeviation="4" />
        </filter>
      </defs>
      <circle cx={c} cy={c} r={R} fill="none" stroke="currentColor" strokeOpacity="0.16" strokeWidth="1" />
      <g className="orbit-spin" style={{ transform: `rotate(${rot.current.deg}deg)` }}>
        {nodes.map((node, i) => {
          const a = ((i * step - 90) * Math.PI) / 180;
          const x = c + R * Math.cos(a);
          const y = c + R * Math.sin(a);
          const isCur = i === current;
          const col = hueVar(node.hue);
          return (
            <g key={i}>
              {isCur && <circle cx={x} cy={y} r={11} fill={col} opacity="0.55" filter={`url(#glow-${id})`} />}
              <circle
                className={isCur ? 'orbit-node-current' : undefined}
                cx={x}
                cy={y}
                r={isCur ? 8 : n > 6 ? 4 : 5}
                fill={node.state === 'future' || node.state === 'rest' ? 'none' : col}
                stroke={col}
                strokeWidth={node.state === 'future' || node.state === 'rest' ? 1.6 : 0}
                opacity={node.state === 'rest' ? 0.5 : 1}
              />
            </g>
          );
        })}
      </g>
      {n > 1 && (
        <text x={c} y={c + 1} textAnchor="middle" dominantBaseline="middle" fill="currentColor" fontSize="15" fontFamily="var(--font-display)" opacity="0.9">
          {current + 1}
          <tspan fontSize="9" opacity="0.6" dx="1">
            /{n}
          </tspan>
        </text>
      )}
    </svg>
  );
}

export function TimerRing({ total, left }: { total: number; left: number }) {
  const r = 46;
  const circ = 2 * Math.PI * r;
  const frac = total > 0 ? Math.max(0, Math.min(1, left / total)) : 0;
  const m = Math.floor(left / 60);
  const s = Math.floor(left % 60);
  return (
    <div className="timer" role="timer" aria-label={`${m} minutes ${s} seconds left`}>
      <svg viewBox="0 0 100 100">
        <circle cx="50" cy="50" r={r} fill="none" stroke="currentColor" strokeOpacity="0.12" strokeWidth="3" />
        <circle
          cx="50" cy="50" r={r} fill="none" stroke="var(--hue, var(--sage))" strokeWidth="3" strokeLinecap="round"
          strokeDasharray={circ} strokeDashoffset={circ * (1 - frac)} style={{ transition: 'stroke-dashoffset 1s linear' }}
        />
      </svg>
      <div className="timer-label">
        <div>
          <div className="t">
            {m}:{String(s).padStart(2, '0')}
          </div>
          <div className="tiny faint mt-8">until the next step</div>
        </div>
      </div>
    </div>
  );
}

/** Growth rings: one per cycle (or week). Oldest in the middle, newest outside. */
export function Rings({ rings, size = 260 }: { rings: Ring[]; size?: number }) {
  const c = size / 2;
  const inner = size * 0.12;
  const outer = size / 2 - 6;
  const count = Math.max(rings.length, 6);
  const gap = (outer - inner) / count;
  const sw = Math.max(2, Math.min(7, gap * 0.62));
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label={`${rings.length} rings`}>
      <circle cx={c} cy={c} r={inner * 0.55} fill="var(--surface-2)" />
      {rings.map((ring, ri) => {
        const r = inner + gap * (ri + 0.5);
        const segs = ring.segments.length;
        const full = Math.max(segs, ring.segments.length < 4 ? 7 : segs);
        const segAngle = (2 * Math.PI) / full;
        const pad = Math.min(0.12, segAngle * 0.18);
        return (
          <g key={ring.from}>
            {ring.segments.map((sg, si) => {
              const a0 = -Math.PI / 2 + si * segAngle + pad / 2;
              const a1 = a0 + segAngle - pad;
              const x0 = c + r * Math.cos(a0);
              const y0 = c + r * Math.sin(a0);
              const x1 = c + r * Math.cos(a1);
              const y1 = c + r * Math.sin(a1);
              const large = a1 - a0 > Math.PI ? 1 : 0;
              return (
                <path
                  key={sg.date}
                  d={`M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1}`}
                  fill="none"
                  stroke={sg.done ? hueVar(sg.hue) : 'var(--line-2)'}
                  strokeWidth={sg.done ? sw : Math.max(1, sw * 0.35)}
                  strokeLinecap="round"
                />
              );
            })}
          </g>
        );
      })}
    </svg>
  );
}

/** Count up from 0 once on mount. */
export function useCountUp(target: number, ms = 900): number {
  const [v, setV] = useState(0);
  useEffect(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setV(target);
      return;
    }
    let raf = 0;
    const t0 = performance.now();
    const tick = (t: number) => {
      const k = Math.min(1, (t - t0) / ms);
      setV(Math.round(target * (1 - Math.pow(1 - k, 3))));
      if (k < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [target, ms]);
  return v;
}
