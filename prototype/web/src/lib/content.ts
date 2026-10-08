// Guidance shown in the app. Every line traces to docs/derm-facts.md
// (fact-checked against AAD, drug labels, DermNet, Cleveland Clinic).
// Rule: hedge ("commonly", "many dermatologists"), never override the derm.

import type { ConflictId } from './engine';
import type { Feeling, ProductKind } from './types';

export interface Source {
  label: string;
  url: string;
}

const S = {
  aadRetinoid: { label: 'AAD: retinoids and retinol', url: 'https://www.aad.org/public/everyday-care/skin-care-secrets/anti-aging/retinoid-retinol' },
  aad20s: { label: 'AAD: skin care in your 20s', url: 'https://www.aad.org/public/everyday-care/skin-care-basics/care/skin-care-in-your-20s' },
  aadSunscreen: { label: 'AAD: how to apply sunscreen', url: 'https://www.aad.org/public/everyday-care/sun-protection/shade-clothing-sunscreen/how-to-apply-sunscreen' },
  aadAcneTreat: { label: 'AAD: acne treatment', url: 'https://www.aad.org/public/diseases/acne/derm-treat/treat' },
  aadExfoliate: { label: 'AAD: exfoliating safely', url: 'https://www.aad.org/public/everyday-care/skin-care-secrets/routine/safely-exfoliate-at-home' },
  aadPhotos: { label: 'AAD: taking pictures of your skin', url: 'https://www.aad.org/public/fad/digital-health/taking-pictures-skin' },
  aadGuideline: { label: 'AAD: 2024 acne guidelines', url: 'https://www.aad.org/news/updated-guidelines-acne-management' },
  ccRetinol: { label: 'Cleveland Clinic: retinol', url: 'https://my.clevelandclinic.org/health/treatments/23293-retinol' },
  dermnetRetinoids: { label: 'DermNet: topical retinoids', url: 'https://dermnetnz.org/topics/topical-retinoids' },
  nhsAdapalene: { label: 'NHS (DBTH) adapalene leaflet', url: 'https://dchft.nhs.uk/leaflets/adapalene-gels-and-cream-differin-and-epiduo/' },
  tretLabel: { label: 'Tretinoin 0.05% label (DailyMed)', url: 'https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=357ed7c9-6ffa-45b8-94be-4d440f5a1c22&type=display' },
  bpoStudy: { label: 'BPO and tretinoin stability (PubMed)', url: 'https://pubmed.ncbi.nlm.nih.gov/9990414/' },
  bowe: { label: 'Dr. Whitney Bowe: skin cycling', url: 'https://drwhitneybowebeauty.com/blogs/derm-scribbles/skin-cycling-dr-bowes-viral-beauty-editor-approved-skincare-method' },
} satisfies Record<string, Source>;

export const DISCLAIMER =
  'Barrier helps you follow the routine your dermatologist gave you. It doesn’t diagnose or give medical advice, and your dermatologist’s instructions always come first.';

export const CONFLICT_NOTE: Record<ConflictId, { title: string; body: string; sources: Source[] }> = {
  'retinoid+exfoliant': {
    title: 'Retinoid and exfoliant on the same night',
    body: 'Both can irritate, so many dermatologists keep them on separate nights. If your dermatologist planned them together, carry on.',
    sources: [S.aadExfoliate, S.ccRetinol],
  },
  'bpo+tretinoin': {
    title: 'Benzoyl peroxide with tretinoin',
    body: 'They’re often prescribed together, but some tretinoin products break down with benzoyl peroxide, so many people use them at different times of day. Use them the way your dermatologist told you.',
    sources: [S.aadGuideline, S.bpoStudy],
  },
};

export const IRRITATION = {
  body: 'If your skin feels raw, tight or stings, it’s common to pause the active for a few nights and use just a gentle cleanser and moisturizer until it calms, then restart less often. Check with your dermatologist about how to pause and restart.',
  call: 'Contact your dermatologist if burning feels severe, if you get swelling, blistering or crusting, or if irritation keeps getting worse instead of settling. If your face, lips or throat swell, or you have trouble breathing, get urgent medical help.',
  sources: [S.tretLabel, S.nhsAdapalene, S.aadAcneTreat],
};

export const PHOTO_TIPS = {
  body: 'Same spot each time, bright window light, plain background, no makeup, no filters. Ask your dermatologist how often they’d like to see them.',
  sources: [S.aadPhotos],
};

export const SKIN_CYCLING_NOTE = {
  body: 'Skin cycling is a popular routine, not a medical treatment, and it may not fit a plan your dermatologist prescribed. If you have a prescription plan, follow that instead.',
  sources: [S.bowe],
};

export const EASE_IN_NOTE = {
  body: 'Dermatologists commonly start a retinoid 2 to 3 nights a week for a couple of weeks, then add nights as skin allows. This is a common pattern, not a rule: set the weeks to match what your dermatologist said.',
  sources: [S.aadRetinoid, S.nhsAdapalene, S.ccRetinol],
};

/** Copy for the "how's it going" card on a retinoid/treatment timeline. */
export function journeyNote(kind: ProductKind, day: number): { title: string; body: string; sources: Source[] } | null {
  const week = Math.floor((day - 1) / 7) + 1;
  if (kind === 'retinoid') {
    if (day <= 21)
      return {
        title: `Week ${week}: settling in`,
        body: 'A little dryness, redness, peeling or mild stinging is common in the first few weeks and often settles within about 2 to 4 weeks. A few extra pimples early on can happen too.',
        sources: [S.tretLabel, S.nhsAdapalene],
      };
    if (day <= 56)
      return {
        title: `Week ${week}: the slow part`,
        body: 'Most acne treatments take about 4 to 8 weeks before you notice fewer breakouts. Skin can look a little worse before it gets better.',
        sources: [S.aadAcneTreat],
      };
    if (day <= 90)
      return {
        title: `Week ${week}: around the check-in point`,
        body: 'Tretinoin for acne is often judged at around 12 weeks. A good time for a comparison photo and a question list for your dermatologist.',
        sources: [S.dermnetRetinoids, S.aadAcneTreat],
      };
    return {
      title: `Week ${week}: the long game`,
      body: 'For fine lines and sun damage, retinoids can take 3 to 6 months or longer. Consistency is the whole trick.',
      sources: [S.tretLabel, S.dermnetRetinoids],
    };
  }
  if (kind === 'treatment') {
    if (day <= 56)
      return {
        title: `Week ${week}`,
        body: 'Most acne treatments take about 4 to 8 weeks before you notice a difference, and clearing can take a few months. Rosacea treatments are often reassessed around 12 weeks.',
        sources: [S.aadAcneTreat],
      };
    return null;
  }
  return null;
}

/** Short tips, filtered by what's in the plan. One shows per day. */
export interface Tip {
  id: string;
  when: (kinds: Set<ProductKind>) => boolean;
  text: string;
  source?: Source;
}

export const TIPS: Tip[] = [
  { id: 'dry', when: (k) => k.has('retinoid'), text: 'Many dermatologists suggest waiting 20 to 30 minutes after washing before a retinoid. Damp skin can feel more irritated.', source: S.aad20s },
  { id: 'pea', when: (k) => k.has('retinoid'), text: 'A pea-sized amount commonly covers the whole face. More won’t work faster.', source: S.ccRetinol },
  { id: 'sun', when: (k) => k.has('retinoid') || k.has('exfoliant'), text: 'Retinoids can make skin more sun-sensitive. Broad-spectrum SPF 30 or higher every morning.', source: S.aadSunscreen },
  { id: 'reapply', when: (k) => k.has('spf'), text: 'Outdoors? Reapply sunscreen about every 2 hours, and after swimming or sweating.', source: S.aadSunscreen },
  { id: 'moist', when: (k) => k.has('retinoid') && k.has('moisturizer'), text: 'Moisturizer before, after, or both? Dermatologists differ. Use the order yours gave you.', source: S.aadRetinoid },
  { id: 'one', when: () => true, text: 'Add one new product at a time, so it’s clear what’s helping and what’s irritating.' },
  { id: 'slow', when: (k) => k.has('treatment') || k.has('retinoid'), text: 'Results usually take 4 to 8 weeks to show. The nights that feel like nothing is happening still count.', source: S.aadAcneTreat },
  { id: 'photo', when: () => true, text: 'Photos beat memory. Same spot, window light, no makeup, and your dermatologist gets to see real progress.', source: S.aadPhotos },
  { id: 'exf', when: (k) => k.has('exfoliant'), text: 'Exfoliating on top of retinoids can mean more dryness. Keep them on separate nights unless your dermatologist says otherwise.', source: S.aadExfoliate },
];

export function tipFor(kinds: Set<ProductKind>, dayNumber: number): Tip {
  const pool = TIPS.filter((t) => t.when(kinds));
  return pool[dayNumber % pool.length];
}

export const FEELINGS: { key: Feeling; label: string; irritation: boolean }[] = [
  { key: 'calm', label: 'Calm', irritation: false },
  { key: 'dry', label: 'Dry', irritation: false },
  { key: 'tight', label: 'Tight', irritation: true },
  { key: 'flaky', label: 'Flaky', irritation: false },
  { key: 'red', label: 'Red', irritation: true },
  { key: 'stinging', label: 'Stinging', irritation: true },
  { key: 'breakout', label: 'Breakout', irritation: false },
];

export const IRRITATION_FEELINGS = new Set(FEELINGS.filter((f) => f.irritation).map((f) => f.key));

export const ALL_SOURCES: Source[] = Object.values(S);
