# Barrier: dermatology fact-check

Checked 2026-10-09. 21 of 25 web searches used. All 12 items covered.

Rule for all app copy: the app supports the routine the user's dermatologist gave them and never replaces it. Where a prescription label or the user's dermatologist differs from anything below, theirs wins. Say that once, plainly, near any schedule or timing content, and use hedges ("commonly", "many dermatologists") instead of rules.

Method: "VERIFIED" means I read the claim on the primary page via a direct fetch (aad.org, DailyMed labels, DermNet, an NHS hospital-trust leaflet, Cleveland Clinic, Dr. Bowe's own site, PubMed abstracts via Europe PMC). "Search only" means it appeared only in a search summary and I did not read the page. Reddit not used. Not reached: nhs.uk has no adapalene or tretinoin cream page I could find (the NHS source used is the Doncaster and Bassetlaw NHS Foundation Trust patient leaflet for adapalene); British Association of Dermatologists leaflets were not found; full text of the 1998 benzoyl peroxide paper is paywalled (abstract only).

---

## Summary: what can go in the app

| # | Topic | Verdict | Ship it? |
|---|-------|---------|----------|
| 1 | Dry skin, wait 20-30 min, pea-size | Partly (AAD and Cleveland Clinic advice; on the label of tretinoin 0.05% emollient cream, not on acne labels) | Yes, hedged |
| 2 | Adjustment period, when to call | Partly (irritation timing solid; "purge lasts 4-6 weeks" is not clinically sourced) | Yes for irritation timing; no for a purge duration |
| 3 | Ramp-up | Confirmed as a common pattern | Yes, as "commonly"; no fixed ladder |
| 4 | Sun and SPF | Confirmed | Yes |
| 5 | Benzoyl peroxide + tretinoin | Confirmed but old and narrow | Yes, softly; never "don't combine" |
| 6 | Retinoid + AHA/BHA same night | Partly (AAD and Cleveland Clinic, no trial) | Yes, softly |
| 7 | Skin cycling | Partly (Bowe's own site confirms the pattern; no clinical evidence) | Optional, low priority |
| 8 | Pause the active when irritated | Confirmed | Yes, defer to the derm |
| 9 | Time to results | Confirmed (ranges) | Yes, as ranges |
| 10 | Moisturizer buffering/sandwich | Partly (moisturizing recognized; "sandwich" has no trial and order varies) | Yes for "moisturizer helps"; no for "sandwich is proven" |
| 11 | Progress photos | Partly (AAD supports photos; consistency tips are common sense, not derm-sourced) | Yes, as practical tips |
| 12 | Azelaic acid / niacinamide / vitamin C "don't combine" | Not confirmed as a real rule | No specific "don't combine" claims |

## Do NOT put these in the app

1. "Purging lasts 4-6 weeks" as a fact. Source is a skincare brand's blog. Use label-backed timing (irritation eases in about 2-4 weeks; new pimples can show up early) instead.
2. "Never use benzoyl peroxide with tretinoin." AAD's 2024 acne guideline gives a strong recommendation for combining benzoyl peroxide and retinoids. The lab finding is real but applies to certain separate tretinoin gels mixed with BPO under light.
3. A claim that nhs.uk says to wait 20 minutes. I could not confirm it on nhs.uk. Cite AAD and Cleveland Clinic.
4. A fixed ramp-up ladder with exact weeks per step. Sources vary (every other night, or 2-3 nights a week, for "a couple of weeks"). Let the user enter their own dermatologist's schedule.
5. Skin cycling (especially the exfoliation night) as a default or as advice for someone on a prescribed retinoid. Bowe's own pages do not address prescription retinoids, and the pattern is from a brand-affiliated site with no clinical trials found.
6. "Niacinamide and vitamin C cancel each other out" (or the reverse "myth debunked" with a citation). No source supports the rule; the best source I fetched (Cleveland Clinic) lists them as compatible. Leave it out.
7. "Hives / rash in new areas" described as retinoid-specific warnings. Reasonable as general allergy signs, but I found no source tying them to retinoids. Phrase as "signs of an allergic reaction".
8. "Avoid flash", "same distance" and "same angle" credited to a dermatology source. Not on the AAD or DermNet pages (see item 11). Fine as app tips, not as cited facts.
9. SPF 50. One NHS trust leaflet says SPF 50 for adapalene; AAD says SPF 30 or higher. Use AAD.
10. A 4-week azelaic acid timeline for everyone. 4 weeks is the acne (20% cream) label; rosacea (15% gel/foam) is reassessed at 12 weeks.

---

## 1. Retinoid on dry skin, wait ~20-30 min, pea-sized amount

VERDICT: PARTLY confirmed.
- Wait 20-30 min after washing: VERIFIED on AAD ("After washing your face, wait 20 to 30 minutes and then apply it", Dr. Baxt, AAD page updated 2/23/23). VERIFIED on the label for tretinoin 0.05% emollient cream (the wrinkle/photoaging product): "Wash gently with mild soap, pat dry, and wait 20-30 minutes." Cleveland Clinic: "Wait 30 minutes after washing your face." Acne labels (Retin-A Micro, Atralin) only say cleanse gently, pat dry, thin layer once daily in the evening; Twyneo says "clean and dry skin".
- Pea-sized for the whole face: VERIFIED on the same 0.05% emollient cream label ("pea-sized amount ... to cover the entire affected face lightly") and Cleveland Clinic ("about the size of a pea", thin layer on the entire face). NOT on the Retin-A Micro or Atralin labels (they say a "thin layer"). So it depends on the product.
- More product does not work faster: VERIFIED (Atralin label: excessive amounts give no incremental efficacy; AAD: applying more than recommended will not clear acne faster, search summary of AAD article).

App-ready: "Many dermatologists suggest washing gently, patting dry, and waiting 20 to 30 minutes before a retinoid, since damp skin can feel more irritated. A pea-sized amount is commonly enough for the whole face, and using more won't work faster. Follow your dermatologist's instructions for your exact product."

Sources:
- https://www.aad.org/public/everyday-care/skin-care-basics/care/skin-care-in-your-20s
- https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=357ed7c9-6ffa-45b8-94be-4d440f5a1c22&type=display (tretinoin 0.05% emollient cream)
- https://my.clevelandclinic.org/health/treatments/23293-retinol
- https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=08ab7e0c-1437-455f-815c-98904d96a289 (Retin-A Micro)
- https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=b6b45969-a64a-4ce3-b3b6-157d2568a301 (Atralin)

---

## 2. Adjustment period ("purging") and when to call the dermatologist

VERDICT: PARTLY confirmed. Irritation timing is well supported; a precise purge duration is not.
- Typical effects: VERIFIED on Retin-A Micro label: "Most common adverse reactions were skin irritation, skin burning, erythema, peeling, dryness, itching, and dermatitis." DermNet: retinoid dermatitis (redness, peeling, dry skin).
- Timing: VERIFIED. Retin-A Micro: irritation "peaked during the initial two weeks of therapy and decreased thereafter." Atralin: appears in the first 2 weeks, peaks around weeks 2-3, and "in some subjects persist[s] throughout the treatment period." Twyneo: rose in the first 2 weeks, then decreased. Adapalene NHS trust leaflet: burning, redness, dryness usually improve within 2-4 weeks. A 2025 meta-analysis (PMC12615114, via Europe PMC) tabulates the adaptation period as "typically 2-4 weeks".
- Early extra pimples: VERIFIED on the Retin-A Micro patient leaflet: "Early in your treatment, you may get new pimples. At this stage, it is important to continue using" it; "an apparent exacerbation of inflammatory acne vulgaris lesions may occur." Cleveland Clinic: "You may still see pimples for the first couple of months of treatment." Caution: one analysis found no clear link between topical retinoids and acne flares (search only), so say "can" not "will".
- "Purge lasts 4-6 weeks, in your usual areas, tiny red bumps = irritation": comes from Dr. Bowe's brand blog (5/17/23). Soft source only.
- When to contact the dermatologist: VERIFIED that "If the irritation is more severe or does not get better, you should stop using it completely and consult your doctor" (NHS trust leaflet); tretinoin "has been reported to cause severe irritation on eczematous or sunburned skin" and stop until healed if sunburned (Atralin); "Contact your doctor if the side effects are a problem" (0.05% emollient label). Kaiser Permanente drug guide (search only): blistering or crusting, severe burning or swelling, skin discoloration; swelling of face/tongue/throat or trouble breathing need urgent care.
- AAD (VERIFIED): irritation does not usually mean an allergy; a dermatologist may adjust amount or frequency.

App-ready (normal): "A little dryness, redness, peeling, or mild stinging is common in the first few weeks and often settles within about 2 to 4 weeks. Some people also notice a few extra pimples early on. Keep going unless your dermatologist says otherwise."
App-ready (call): "Contact your dermatologist if burning feels severe, if you get swelling, blistering or crusting, or if irritation keeps getting worse instead of settling. If your face, lips, or throat swell, or you have trouble breathing, get urgent medical help."

Sources: Retin-A Micro, Atralin, 0.05% emollient labels (above); https://dchft.nhs.uk/leaflets/adapalene-gels-and-cream-differin-and-epiduo/ ; https://my.clevelandclinic.org/health/treatments/23293-retinol ; https://www.aad.org/public/diseases/acne/derm-treat/treat ; https://drwhitneybowebeauty.com/blogs/derm-scribbles/how-to-tell-if-your-skin-is-purging-or-breaking-out (brand blog)

---

## 3. Ramp-up schedule

VERDICT: CONFIRMED as a common pattern; exact step lengths are not standardized.
- AAD news release (10/25/22), Dr. Paul Yamauchi (UCLA): "try using them two to three times per week for a couple of weeks or so", then apply more often if "you don't see any excessive irritation". VERIFIED.
- AAD "Retinoid or retinol?" (5/25/21), Dr. Tina Alster: "every other night to start, slowly building up". VERIFIED.
- NHS trust leaflet (adapalene): start with two to three applications a week, then gradually increase to nightly as the skin tolerates it. VERIFIED.
- Cleveland Clinic: every other day for the first couple of weeks, then ramp up. VERIFIED.
- Search only: clinic handouts that start every 2nd or 3rd night then go nightly "only as tolerated", or every other night and nightly after 2 weeks with no irritation; a 1998 JAAD practical guide (alternate nights or every third night for 1-2 weeks).

App-ready: "Dermatologists commonly start a retinoid 2 to 3 nights a week for a couple of weeks, then add nights if your skin handles it, working toward every night. Your dermatologist's schedule comes first."

Sources: https://www.aad.org/news/national-healthy-skin-dermatologists-provide-tips-on-skin-hair-nails ; https://www.aad.org/public/everyday-care/skin-care-secrets/anti-aging/retinoid-retinol ; https://dchft.nhs.uk/leaflets/adapalene-gels-and-cream-differin-and-epiduo/ ; https://my.clevelandclinic.org/health/treatments/23293-retinol

---

## 4. Retinoids and sun

VERDICT: CONFIRMED.
- Retinoids can increase sun sensitivity: VERIFIED (DermNet: "Topical retinoids can cause photosensitivity."; Retin-A Micro and Atralin labels: minimize UV exposure, use sunscreen daily; stop until healed if sunburned; AAD: use retinoids at night, protect skin by day with shade, clothing, sunscreen).
- AAD sunscreen page (updated 8/15/25): SPF 30 or higher, broad-spectrum, water resistant; "reapply sunscreen every two hours, and immediately after swimming or sweating"; apply about 15 minutes before going out; about 1 oz (shot glass) for exposed skin, at least a teaspoon for the face.

App-ready: "Retinoids can make skin more sensitive to sun. Use a broad-spectrum SPF 30 or higher every morning, and reapply about every 2 hours when you're outdoors and after swimming or sweating."

Sources: https://www.aad.org/public/everyday-care/sun-protection/shade-clothing-sunscreen/how-to-apply-sunscreen ; https://dermnetnz.org/topics/topical-retinoids ; https://www.aad.org/public/everyday-care/skin-care-secrets/anti-aging/retinoid-retinol ; Retin-A Micro and Atralin labels (above)

---

## 5. Benzoyl peroxide (BPO) with tretinoin

VERDICT: CONFIRMED but dated and narrow. Do not state as a blanket rule.
- Chemistry: Martin et al., Br J Dermatol 1998;139 Suppl 52:8-11 (Galderma-affiliated authors). They mixed commercial 0.1% adapalene gel and 0.025% tretinoin gel with an equal volume of 10% BPO lotion and exposed it to light for 24 hours. "Adapalene exhibits a remarkable stability"; tretinoin "is very sensitive to light and oxidation", with BPO plus light degrading over 50% of the tretinoin in about 2 hours and 95% in 24 hours. VERIFIED via abstract (PubMed 9990414). Caveats: lab mixing of two separate products, sponsor-affiliated, from 1998.
- Formulation matters: Nighland et al., Cutis 2006;77(5):313-6 (VERIFIED via abstract). Under simulated sunlight, tretinoin gel microsphere 0.1% retained about 94% of its tretinoin at 2 h and 84% at 6 h, versus 19% and 10% for a conventional 0.025% gel. Combined with an erythromycin-BPO gel the conventional gel fell to 7% and 0%. This tested light exposure, so it does not isolate BPO oxidation. A microsphere tretinoin gel is more stable, so "microsphere is stable" is supported for light, and supported with BPO only by that one study.
- Products built to be used together: Twyneo (tretinoin 0.1% + BPO 3%) uses silica core-shell structures to separately micro-encapsulate tretinoin and BPO crystals (VERIFIED on the DailyMed label). Adapalene + BPO (Epiduo) is an approved combination; DermNet lists it. 
- AAD 2024 acne guideline (VERIFIED): strong recommendation for "combinations of topical benzoyl peroxide, retinoids, or the above antibiotics"; topical retinoids also strongly recommended.
- Irritation caveat (VERIFIED on labels): Atralin: "Particular caution should be exercised with acne preparations containing benzoyl peroxide ... Allow the effects of such preparations to subside before use of Atralin Gel has begun"; Retin-A Micro: BPO, sulfur, resorcinol or salicylic acid "may increase the risk" of irritation.
- NHS trust leaflet (VERIFIED): BPO, clindamycin or erythromycin can be used at a different time of day (example given: adapalene in the morning and the other treatment at night).

App-ready: "Benzoyl peroxide and retinoids are often prescribed together. Some separate tretinoin products can break down when mixed with benzoyl peroxide, and the pair can also irritate, so many people use them at different times of day. Use them the way your dermatologist told you."

Sources: https://pubmed.ncbi.nlm.nih.gov/9990414/ ; https://pubmed.ncbi.nlm.nih.gov/16776288/ ; https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=654ae869-5bc0-40b3-a423-dcc3270c05d8 ; https://www.aad.org/news/updated-guidelines-acne-management ; https://dchft.nhs.uk/leaflets/adapalene-gels-and-cream-differin-and-epiduo/ ; https://dermnetnz.org/topics/benzoyl-peroxide

---

## 6. Retinoid + AHA/BHA exfoliant on the same night

VERDICT: PARTLY confirmed (consistent practical advice, no trial).
- AAD (VERIFIED, "How to safely exfoliate at home"): prescription retinoid creams, retinol, and benzoyl peroxide can make skin more sensitive or peel; "Exfoliating while using these products may worsen dry skin or even cause acne breakouts." The page does not name AHAs/BHAs specifically.
- NHS trust leaflet (VERIFIED): avoid peeling agents such as salicylic or glycolic acid while on adapalene.
- Cleveland Clinic glycolic acid page (VERIFIED): when starting, you "may want to avoid using glycolic acid with" other exfoliants, retinol, and vitamin C serums, to reduce active ingredients and spot the culprit. Cleveland Clinic retinol page (search only): if you want both, alternate days, or use acid in the morning and retinol at night.
- Labels (VERIFIED): other topical acne products "may increase the irritation".

App-ready: "Retinoids and exfoliating acids can both irritate skin, so using them on the same night often leads to more dryness and stinging. Many dermatologists suggest keeping them on separate nights, or skipping the exfoliant unless your dermatologist includes one. Ask before adding one."

Sources: https://www.aad.org/public/everyday-care/skin-care-secrets/routine/safely-exfoliate-at-home ; https://dchft.nhs.uk/leaflets/adapalene-gels-and-cream-differin-and-epiduo/ ; https://health.clevelandclinic.org/glycolic-acid

---

## 7. Skin cycling (Dr. Whitney Bowe)

VERDICT: PARTLY confirmed. The pattern is accurate to Bowe's own pages. No clinical trials found; it is a brand-affiliated (she sells a Skin Cycling Program), social-media-born routine.
- 4-night cycle (VERIFIED, her site, 8/11/22): Night 1 exfoliation (chemical exfoliant, "no gritty scrubs"), Night 2 retinoid, Nights 3 and 4 recovery (hold acids and retinoids, focus on hydration and barrier repair). Repeat.
- When to expect results (VERIFIED, same page): "After two full cycles", blotchiness and sensitivity should be much improved and skin more hydrated and softer; fine lines, wrinkles, breakouts, and dark spots can start to improve over "the next few months" of consistent use. So "two cycles" (about 8 nights) is her claim for sensitivity/blotchiness only, not for acne or lines.
- Beginners/sensitive skin (VERIFIED, her site, 10/20/22): she says the classic cycle works well for sensitive skin, but for extra-sensitive or beginners, introduce actives one at a time: start with one "push" night followed by three recovery nights and keep that pattern for 2-3 weeks; add the retinoid night only if there is no irritation, burning, stinging, or peeling; start with an over-the-counter retinol or retinal rather than prescription strength; put a fragrance-free moisturizer on sensitive areas first (a second moisturizer layer is her "sandwich"). Search only: Bustle quoted her suggesting five nights for rosacea and three for oily/acne-prone skin.
- Prescription retinoids: her pages do not address them (VERIFIED absence). For someone with a prescribed schedule, the prescribed schedule wins.

App-ready (only if included as an optional label): "Skin cycling is a popular routine that alternates an exfoliating night, a retinoid night, and two recovery nights. It isn't a medical treatment, and it may not fit a routine your dermatologist prescribed. If you have a prescription plan, follow that instead."

Sources: https://drwhitneybowebeauty.com/blogs/derm-scribbles/skin-cycling-dr-bowes-viral-beauty-editor-approved-skincare-method ; https://drwhitneybowebeauty.com/blogs/derm-scribbles/6-tips-for-skin-cycling-with-sensitive-skin

---

## 8. Irritation from actives: pause, simplify, resume less often

VERDICT: CONFIRMED (as common advice that the prescriber should direct).
- Tretinoin 0.05% emollient cream label (VERIFIED): for local irritation, "use less medication, decrease the frequency of application, discontinue use temporarily, or discontinue use altogether."
- NHS trust leaflet (VERIFIED): "If your skin becomes very irritated, apply it less often or stop temporarily"; if severe or not improving, stop completely and consult your doctor.
- AAD (VERIFIED): the dermatologist may adjust amount or frequency; irritation doesn't usually mean allergy. AAD's retinoid article (search summary) adds "make these changes only with their guidance".
- Atralin label (VERIFIED): use an appropriate moisturizer for dryness. Azelaic acid labels (VERIFIED, Azelex and Finacea): "If troublesome irritation persists, use should be discontinued, and patients should consult their physician."
- The exact wording "pause for a few nights, gentle cleanser and moisturizer only, then restart every 2nd-3rd night" appears in clinic handouts (search only, page not readable). The principle is supported; the specific "few nights" is not label-sourced.

App-ready: "If your skin feels raw, tight, or stings, it's common to pause the active for a few nights and use just a gentle cleanser and moisturizer until it calms, then restart less often. Check with your dermatologist about how to pause and restart, and contact them if it doesn't settle."

Sources: https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=357ed7c9-6ffa-45b8-94be-4d440f5a1c22&type=display ; https://dchft.nhs.uk/leaflets/adapalene-gels-and-cream-differin-and-epiduo/ ; https://www.aad.org/public/diseases/acne/derm-treat/treat ; https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=0d5269d5-6555-4d2c-bc3b-df862b014275&type=display (Azelex)

---

## 9. Typical time to see results

VERDICT: CONFIRMED as ranges. Give ranges, not promises.
- Acne, topical treatments in general (AAD, VERIFIED): "it takes at least 6 to 8 weeks before you start to see fewer breakouts" (AAD acne treatment page); adult acne page: fewer breakouts in about 4-8 weeks, clearing around 16 weeks, use one product 6-8 weeks before judging; "9 things to try when acne won't clear" page (9/12/23): at least 4 weeks to work, improvement in 4-6 weeks, clearing can take "two to three months or longer". So "4-8 weeks to start, up to a few months to clear" fits all three AAD pages.
- Tretinoin for acne: Retin-A Micro leaflet (VERIFIED): improvement "may be noticed after 2 weeks"; more than 7 weeks may be needed for full benefit; Atralin and Twyneo trials measured efficacy at week 12; DermNet: "may take 12 weeks or longer"; NHS trust leaflet: most need "at least a couple of months". So ~8-12 weeks is supported (12 weeks is the trial endpoint).
- Tretinoin for photoaging: 0.05% emollient label (VERIFIED): "you may notice some effects in 3 to 4 months"; "up to six months of therapy may be required"; it palliates fine wrinkles and does not eliminate them. DermNet: benefit with long-term use (over 6 months).
- Azelaic acid: acne, 20% cream (Azelex label, VERIFIED): "Improvement ... occurs in the majority of patients with inflammatory lesions within four weeks." DermNet (VERIFIED): some improvement after one month, maximum after about six months. Rosacea, 15% gel (Finacea label, VERIFIED): "reassessed if no improvement ... upon completing 12 weeks".
- Benzoyl peroxide: DermNet: "may take several months to notice an improvement" (VERIFIED).

App-ready: "Most acne treatments take about 4 to 8 weeks before you notice fewer breakouts, and clearing can take a few months. Tretinoin for acne is often judged at around 12 weeks, and for fine lines and sun damage it can take 3 to 6 months or longer. Skin can look a little worse before it gets better, so stick with the plan and check in with your dermatologist."

Sources: https://www.aad.org/public/diseases/acne/derm-treat/treat ; https://www.aad.org/public/diseases/acne/diy/adult-acne-treatment ; https://www.aad.org/public/diseases/acne/diy/wont-clear ; https://dermnetnz.org/topics/topical-retinoids ; https://dermnetnz.org/topics/azelaic-acid ; Retin-A Micro, 0.05% emollient, Azelex, Finacea labels

---

## 10. Moisturizer "buffering" / sandwich method

VERDICT: PARTLY confirmed. Using moisturizer to reduce retinoid irritation is recognized. The specific "sandwich" is not an established, trialed protocol, and the order (before vs after) differs between sources.
- AAD (VERIFIED, 2/23/23): "If you find the retinoid too drying, apply a moisturizer immediately after washing your face", then the retinoid 20-30 minutes later. AAD (VERIFIED, 5/25/21): "starting slowly and using moisturizer will help mitigate" irritation and dark marks. AAD news release (VERIFIED, 10/25/22): Dr. Vatanchi suggests petroleum jelly or a hydrating moisturizer around the eyes and corners of nose and mouth before a retinoid.
- Other orders: NHS trust leaflet says moisturizer only after the adapalene has been absorbed; the Atralin label recommends an appropriate moisturizer for dryness (VERIFIED, no order given). 
- "Sandwich" (moisturizer, retinoid, moisturizer): named by Dr. Bowe (VERIFIED on her site: "If skin is dry, a second moisturizer layer is the 'sandwich' technique"). Search only: a 2024 review (PMC11344648) lists a moisturizer-retinol-moisturizer "sandwich" as something to explore and says adoption should await controlled trials; I found no trial comparing it with other approaches. A 1998 JAAD guide (search only) advised against nighttime moisturizer with tretinoin, which is dated.

App-ready: "A fragrance-free moisturizer can make a retinoid more comfortable. Some dermatologists have you apply it before the retinoid, some after, and some both ('sandwiching'). Use whichever order your dermatologist gave you."

Sources: https://www.aad.org/public/everyday-care/skin-care-basics/care/skin-care-in-your-20s ; https://www.aad.org/public/everyday-care/skin-care-secrets/anti-aging/retinoid-retinol ; https://www.aad.org/news/national-healthy-skin-dermatologists-provide-tips-on-skin-hair-nails ; https://drwhitneybowebeauty.com/blogs/derm-scribbles/6-tips-for-skin-cycling-with-sensitive-skin ; https://pmc.ncbi.nlm.nih.gov/articles/PMC11344648/

---

## 11. Progress photos

VERDICT: PARTLY confirmed. AAD endorses photos for tracking treatment, and has lighting/background/makeup tips. It does NOT give same-angle or same-distance consistency rules, and does not mention flash. Those are sensible practice, not cited derm guidance.
- AAD "How to take pictures of your skin for your dermatologist" (VERIFIED, updated 7/20/23): photos show "how well your treatment is working"; use natural, bright light such as from a window (desk lamp only if no natural light), light in front of you not behind; neutral, one-color background; remove makeup (and wait for irritation to fade if removal causes redness); take a few shot types (overview, comparison, close-up) and a coin or ruler for scale; ask your dermatologist how often to take pictures. Flash and consistency between sessions are not covered.
- DermNet "Image acquisition in dermatology" (VERIFIED): clinical photography guidance (good lighting, simple background, fill the frame, avoid wide-angle distortion); it does not discuss serial photos and it allows flash (diffuse it, or take one with and one without). So do not claim a derm source says "no flash".
- Search only: a PubMed study of acne remote assessment found patient-taken photos could be rated most of the time (89%) (PubMed 19548822).

App-ready: "Photos can show how your treatment is working. Take them in the same spot each time, in bright natural light (a window works well), with a plain background and no makeup, and without filters. Ask your dermatologist how often they'd like to see them."
(The "same spot each time" and "no filters" parts are practical tips, not quotes from AAD.)

Sources: https://www.aad.org/public/fad/digital-health/taking-pictures-skin ; https://dermnetnz.org/topics/image-acquisition-in-dermatology ; https://pubmed.ncbi.nlm.nih.gov/19548822

---

## 12. Azelaic acid, niacinamide, vitamin C: "don't combine" myths

VERDICT: NOT confirmed as real rules. Only include if the app wants general caution.
- Niacinamide (Cleveland Clinic, VERIFIED): pairs well with vitamin C, retinol, glycolic acid, hyaluronic acid; the article has no "don't combine" warnings for any active; it may "soothe irritation caused by strong exfoliants, like retinol or glycolic acid"; only caveat is "not using too many skin care products with it at once". Generally gentle; rare itching, burning, redness; patch test if sensitive.
- Niacinamide + vitamin C "flushing/cancel out": I found no study or dermatology source supporting it. A search summary noted flushing is a property of niacin (nicotinic acid), a different molecule from niacinamide; unverified. Treat the whole thing as unconfirmed and leave it out.
- Azelaic acid (DermNet, VERIFIED): does not cause photosensitivity; no guidance on combining with niacinamide or vitamin C. Mayo Clinic (search only, page blocked): azelaic acid often works with other serum ingredients such as vitamin C and niacinamide. One melasma study combined 20% azelaic acid with 0.05% tretinoin (search only).
- Real, sourced caution (VERIFIED, Cleveland Clinic): when starting, avoid layering several strong actives (glycolic acid with retinol, other exfoliants, vitamin C) so you can tell which product is causing a problem. Introduce one new product at a time.

App-ready (general only): "Introduce one new active at a time so it's clear what's helping or irritating your skin, and ask your dermatologist before combining strong actives."

Sources: https://health.clevelandclinic.org/niacinamide ; https://health.clevelandclinic.org/glycolic-acid ; https://dermnetnz.org/topics/azelaic-acid

---

## Source quality notes

- Strong: AAD pages (dates above), DailyMed/FDA labels, DermNet, PubMed abstracts, AAD 2024 acne guideline release.
- Medium: Cleveland Clinic (non-profit hospital, consumer pages), NHS Foundation Trust patient leaflet (adapalene; applies to adapalene products specifically).
- Weak, use only as soft support: Dr. Bowe's own site (brand-affiliated; used for what her routine is, not for clinical claims), clinic blog posts (Derick Dermatology 2013).
- Not reachable: nhs.uk adapalene/tretinoin cream page; BAD patient leaflets; Mayo Clinic wrinkle-cream page (403); two clinic PDF handouts (403/520); Azelex FDA PDF (unreadable, used DailyMed instead); PubMed/PMC HTML pages (cookie wall; abstracts read via Europe PMC).
