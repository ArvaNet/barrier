/*
 * Routine codes, version 1: the rules, the encoder and the words.
 *
 * A faithful port of Packages/BarrierCore/Sources/BarrierCore/PlanCode.swift
 * (checked(), the unknown-key checks, Limit, Wire, summary) and of
 * Engine.describe. The format is documented in docs/plan-code.md.
 * PlanCodeToolTests.swift locks this encoder to the app's decoder.
 *
 * Works in the browser (window.PlanCode) and in node (require).
 * No dependencies. Nothing is sent or stored.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.PlanCode = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var VERSION = 1;
  var LINK_PREFIX = "barrier://plan/";

  var Limit = {
    payload: 2600, // characters in the payload
    products: 24,
    steps: 16,
    name: 80,
    note: 280,
    amount: 120,
    how: 200,
    clinic: 60,
    bodyName: 24,
    cue: 40,
    waitMin: 120,
    courseDays: 730,
    rotation: 12, // Engine.maxRotation
    // Starting slowly: what the app's step editor lets a person set.
    stages: 4,
    stageEveryMin: 2,
    stageEveryMax: 4,
    stageWeeksMax: 8,
  };

  // Evening first, as everywhere in the app (Slot.ordered).
  var SLOTS = ["pm", "am", "body", "body2"];
  var BODY = { body: true, body2: true };
  var KINDS = ["cleanser", "retinoid", "exfoliant", "treatment", "serum", "moisturizer", "spf", "oral", "other"];
  var ACTIVE = { retinoid: true, exfoliant: true, treatment: true };
  var SLOT_TITLE = { am: "Morning", pm: "Evening", body: "Body", body2: "Body" };
  var SLOT_WORD = { am: "morning", pm: "night", body: "day", body2: "day" };

  var KEYS = {
    code: ["v", "c", "p", "am", "pm", "body", "body2", "i"],
    product: ["n", "k", "o", "d"],
    routine: ["l", "s", "n", "q"],
    step: ["p", "a", "h", "w", "n", "d", "b"],
  };

  function stageEveryRule(step) { return step + ": each stage is every 2nd, 3rd or 4th time, and less often than the goal"; }
  function stageDaysRule(step) { return step + ": each stage is 1 to 8 whole weeks (7 to 56 days)"; }

  // MARK: Small helpers

  function isObject(x) { return x !== null && typeof x === "object" && !Array.isArray(x); }
  function isInt(x) { return typeof x === "number" && Number.isInteger(x); }
  function has(o, k) { return Object.prototype.hasOwnProperty.call(o, k) && o[k] !== null && o[k] !== undefined; }

  // Swift's CharacterSet.whitespacesAndNewlines: Unicode Z* plus U+0009-U+000D and U+0085.
  var WS = "\\u0009-\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000";
  var TRIM = new RegExp("^[" + WS + "]+|[" + WS + "]+$", "g");

  // Swift's String.count: user-perceived characters (grapheme clusters).
  var segmenter = typeof Intl !== "undefined" && Intl.Segmenter ? new Intl.Segmenter("en", { granularity: "grapheme" }) : null;
  function characters(s) {
    if (segmenter) { var n = 0; var it = segmenter.segment(s)[Symbol.iterator](); while (!it.next().done) n++; return n; }
    return Array.from(s).length;
  }

  /* Trimmed, or null when empty. Refuses control characters and text that changes reading direction. */
  function text(s, max, what, problems, multiline) {
    if (s === null || s === undefined) return null;
    var t = s.replace(TRIM, "");
    if (t === "") return null;
    for (var i = 0; i < t.length; i++) {
      var v = t.codePointAt(i);
      if (v > 0xffff) i++;
      var control = v < 0x20 || (v >= 0x7f && v <= 0x9f);
      var direction = (v >= 0x202a && v <= 0x202e) || (v >= 0x2066 && v <= 0x2069);
      if (direction || (control && !(multiline && v === 0x0a))) {
        problems.push(what + " has characters that can't be shown");
        return t;
      }
    }
    if (characters(t) > max) problems.push(what + " is longer than " + max + " characters");
    return t;
  }

  // MARK: Reading: version, unknown keys, shape

  function only(object, allowed, what, problems) {
    if (!isObject(object)) return;
    var extra = Object.keys(object).sort().filter(function (k) { return allowed.indexOf(k) < 0; });
    if (extra.length) problems.push(what + " has an unknown key \"" + extra[0] + "\"");
  }

  // The same shape the app's decoder accepts. null counts as absent for optional keys.
  function shape(obj) {
    var out = [];
    function str(o, k, where, required) {
      if (!has(o, k)) { if (required) out.push("wrong shape: " + where + " needs \"" + k + "\""); return; }
      if (typeof o[k] !== "string") out.push("wrong shape: " + where + " \"" + k + "\" must be text");
    }
    function int(o, k, where, required) {
      if (!has(o, k)) { if (required) out.push("wrong shape: " + where + " needs \"" + k + "\""); return; }
      if (!isInt(o[k])) out.push("wrong shape: " + where + " \"" + k + "\" must be a whole number");
    }
    function ints(o, k, where) {
      if (!has(o, k)) return;
      if (!Array.isArray(o[k]) || !o[k].every(isInt)) out.push("wrong shape: " + where + " \"" + k + "\" must be a list of whole numbers");
    }
    str(obj, "c", "the code", false);
    str(obj, "i", "the code", false);
    if (!has(obj, "p")) out.push("wrong shape: the code needs \"p\"");
    else if (!Array.isArray(obj.p)) out.push("wrong shape: \"p\" must be a list of products");
    else obj.p.forEach(function (p, i) {
      var where = "product " + (i + 1);
      if (!isObject(p)) { out.push("wrong shape: " + where + " must be an object"); return; }
      str(p, "n", where, true); str(p, "k", where, true); str(p, "o", where, false); int(p, "d", where, false);
    });
    SLOTS.forEach(function (slot) {
      if (!has(obj, slot)) return;
      var r = obj[slot];
      var where = "the " + slot + " routine";
      if (!isObject(r)) { out.push("wrong shape: " + where + " must be an object"); return; }
      int(r, "l", where, false); str(r, "n", where, false); str(r, "q", where, false);
      if (!has(r, "s")) out.push("wrong shape: " + where + " needs \"s\"");
      else if (!Array.isArray(r.s)) out.push("wrong shape: " + where + " \"s\" must be a list of steps");
      else r.s.forEach(function (s, n) {
        var w = where + ", step " + (n + 1);
        if (!isObject(s)) { out.push("wrong shape: " + w + " must be an object"); return; }
        int(s, "p", w, true); str(s, "a", w, false); str(s, "h", w, false); int(s, "w", w, false); ints(s, "n", w); ints(s, "d", w);
        if (has(s, "b") && !(Array.isArray(s.b) && s.b.every(function (x) { return Array.isArray(x) && x.every(isInt); }))) {
          out.push("wrong shape: " + w + " \"b\" must be a list of [every, days]");
        }
      });
    });
    return out;
  }

  // MARK: The rules (PlanCode.checked)

  function analyze(obj) {
    var problems = [];
    if (!isObject(obj)) return { problems: ["unreadable: a code is one JSON object"], code: null };

    if (!isInt(obj.v)) return { problems: ["no version"], code: null };
    if (obj.v > VERSION) return { problems: ["made for a newer version of the format"], code: null };
    if (obj.v !== VERSION) return { problems: ["version " + obj.v], code: null };

    only(obj, KEYS.code, "the code", problems);
    if (Array.isArray(obj.p)) obj.p.forEach(function (p) { only(p, KEYS.product, "a product", problems); });
    SLOTS.forEach(function (slot) {
      var r = obj[slot];
      only(r, KEYS.routine, "the " + slot + " routine", problems);
      if (isObject(r) && Array.isArray(r.s)) r.s.forEach(function (s) { only(s, KEYS.step, "a step", problems); });
    });
    if (problems.length) return { problems: problems, code: null };
    problems = shape(obj);
    if (problems.length) return { problems: problems, code: null };

    // What the app's decoder refuses while building the code.
    obj.p.forEach(function (p, i) {
      if (KINDS.indexOf(p.k) < 0) problems.push("product " + (i + 1) + ": unknown kind \"" + p.k + "\"");
    });
    SLOTS.forEach(function (slot) {
      var r = obj[slot];
      if (!has(obj, slot)) return;
      r.s.forEach(function (s, n) {
        var step = "the " + slot + " routine, step " + (n + 1);
        if (has(s, "n") && has(s, "d")) problems.push("a step has both rotation positions and weekdays");
        if (!has(s, "b")) return;
        s.b.forEach(function (pair) {
          if (pair.length !== 2) problems.push(step + ": a stage is [every, days]");
          else if (pair[0] < Limit.stageEveryMin || pair[0] > Limit.stageEveryMax) problems.push(stageEveryRule(step));
          else if (pair[1] < 7) problems.push(stageDaysRule(step));
        });
        if (s.b.length === 0) problems.push(step + ": an empty build-up");
      });
    });
    if (problems.length) return { problems: problems, code: null };

    var out = { v: VERSION };
    var clinic = text(obj.c, Limit.clinic, "the clinic name", problems);
    var ifIrritated = text(obj.i, Limit.note, "the irritation note", problems, true);

    if (obj.p.length < 1 || obj.p.length > Limit.products) problems.push("needs 1 to " + Limit.products + " products");
    var products = obj.p.map(function (p, i) {
      var label = "product " + (i + 1);
      var name = text(p.n, Limit.name, label + "'s name", problems);
      if (name === null) problems.push(label + " has no name");
      if (has(p, "d") && !(p.d >= 1 && p.d <= Limit.courseDays)) problems.push(label + ": a course is 1 to " + Limit.courseDays + " days");
      var note = text(p.o, Limit.note, label + "'s note", problems, true);
      var item = { k: p.k, n: name };
      if (has(p, "d")) item.d = p.d;
      if (note !== null) item.o = note;
      return item;
    });

    var present = SLOTS.filter(function (slot) { return has(obj, slot); });
    if (present.length === 0) problems.push("no routine");
    var faceUse = {};
    var bodyUse = {};
    var routines = {};
    present.forEach(function (slot) {
      var r = obj[slot];
      var what = "the " + slot + " routine";
      var length = has(r, "l") ? r.l : 1;
      if (!(length >= 1 && length <= Limit.rotation)) problems.push(what + ": a rotation is 1 to " + Limit.rotation + " long");
      if (r.s.length < 1 || r.s.length > Limit.steps) problems.push(what + " needs 1 to " + Limit.steps + " steps");

      var seen = {};
      var usesNights = false;
      var steps = r.s.map(function (line, n) {
        var step = what + ", step " + (n + 1);
        if (!(line.p >= 0 && line.p < products.length)) { problems.push(step + ": no such product"); return null; }
        if (seen[line.p]) { problems.push(step + ": the product is already in this routine"); return null; }
        seen[line.p] = true;
        var on = { all: true };
        if (has(line, "n")) {
          var nights = line.n;
          var okN = nights.length > 0 && new Set(nights).size === nights.length &&
            nights.every(function (x) { return x >= 0 && x < length; });
          if (!okN) problems.push(step + ": bad rotation positions");
          // On every position is the same as "every time".
          on = okN && nights.length === length ? { all: true } : { n: nights.slice().sort(function (a, b) { return a - b; }) };
        } else if (has(line, "d")) {
          var days = line.d;
          var okD = days.length > 0 && new Set(days).size === days.length && days.every(function (x) { return x >= 0 && x <= 6; });
          if (!okD) problems.push(step + ": bad weekdays");
          on = { d: days.slice().sort(function (a, b) { return a - b; }) };
        }
        if (has(line, "w") && !(line.w >= 1 && line.w <= Limit.waitMin)) problems.push(step + ": a wait is 1 to " + Limit.waitMin + " minutes");
        if (on.n) usesNights = true;

        // Starting slowly: only what the step editor offers.
        if (has(line, "b")) {
          var goal = every(on, length);
          if (!ACTIVE[products[line.p].k]) problems.push(step + ": only a retinoid, exfoliant or treatment starts slowly");
          else if (goal === null) problems.push(step + ": starting slowly needs a goal of every time or every Nth, not weekdays or picked days");
          else if (line.b.length > Limit.stages) problems.push(step + ": a build-up has 1 to " + Limit.stages + " stages");
          else {
            for (var k = 0; k < line.b.length; k++) {
              var st = line.b[k];
              if (!(st[0] >= Limit.stageEveryMin && st[0] <= Limit.stageEveryMax && st[0] > goal)) { problems.push(stageEveryRule(step)); break; }
              if (!(st[1] % 7 === 0 && st[1] >= 7 && st[1] <= 7 * Limit.stageWeeksMax)) { problems.push(stageDaysRule(step)); break; }
              if (k > 0 && st[0] > line.b[k - 1][0]) { problems.push(step + ": the stages go from the slowest to the fastest"); break; }
            }
          }
        }
        var s = { p: line.p };
        var a = text(line.a, Limit.amount, step + ": the amount", problems);
        var h = text(line.h, Limit.how, step + ": the how-to", problems, true);
        if (a !== null) s.a = a;
        if (h !== null) s.h = h;
        if (has(line, "w")) s.w = line.w;
        if (on.n) s.n = on.n;
        if (on.d) s.d = on.d;
        if (has(line, "b")) s.b = line.b.map(function (st) { return [st[0], st[1]]; });
        return s;
      });

      var routine = { s: steps };
      if (BODY[slot]) {
        var name = text(r.n, Limit.bodyName, "the " + slot + " routine's name", problems);
        if (name === null) problems.push("the " + slot + " routine needs a name");
        var cue = text(r.q, Limit.cue, "the " + slot + " routine's cue", problems);
        if (name !== null) routine.n = name;
        if (cue !== null) routine.q = cue;
        Object.keys(seen).forEach(function (k) { bodyUse[k] = true; });
      } else {
        if (has(r, "n") || has(r, "q")) problems.push(what + ": only a body routine has a name or a cue");
        Object.keys(seen).forEach(function (k) { faceUse[k] = true; });
      }
      // A rotation no step uses is the same routine every time.
      if (usesNights && length !== 1) routine.l = length;
      routines[slot] = routine;
    });

    if (present.length) {
      var used = Object.assign({}, faceUse, bodyUse);
      if (Object.keys(used).length !== products.length) problems.push("a product isn't used by any step");
      // Face and body keep their own products. The two body routines may share.
      if (Object.keys(faceUse).some(function (k) { return bodyUse[k]; })) problems.push("a product is in both a face and a body routine");
    }
    if (problems.length) return { problems: problems, code: null };

    // Nothing loads halfway: every build-up must fit its rotation, placed as the app places it.
    present.forEach(function (slot) {
      if (!fits(routines[slot])) problems.push("the " + slot + " routine: a build-up doesn't fit the rotation");
    });
    if (problems.length) return { problems: problems, code: null };

    if (clinic !== null) out.c = clinic;
    out.p = products;
    present.forEach(function (slot) { out[slot] = routines[slot]; });
    if (ifIrritated !== null) out.i = ifIrritated;
    if (payloadOf(out).length > Limit.payload) return { problems: ["too much text to fit in one code"], code: null };
    return { problems: [], code: out };
  }

  // MARK: Text form

  // Compact JSON with sorted keys, as the app writes it.
  function canonical(x) {
    if (Array.isArray(x)) return "[" + x.map(canonical).join(",") + "]";
    if (isObject(x)) {
      return "{" + Object.keys(x).sort().map(function (k) { return JSON.stringify(k) + ":" + canonical(x[k]); }).join(",") + "}";
    }
    return JSON.stringify(x);
  }

  var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  function base64url(bytes) {
    var out = "";
    for (var i = 0; i < bytes.length; i += 3) {
      var a = bytes[i], b = bytes[i + 1], c = bytes[i + 2];
      out += B64[a >> 2] + B64[((a & 3) << 4) | ((b || 0) >> 4)];
      if (b !== undefined) out += B64[((b & 15) << 2) | ((c || 0) >> 6)];
      if (c !== undefined) out += B64[c & 63];
    }
    return out;
  }

  function payloadOf(code) { return base64url(new TextEncoder().encode(canonical(code))); }

  /** Plain-English problems; an empty list means the app will accept the code. */
  function validate(obj) { return analyze(obj).problems; }

  /** The code as the app stores it: text trimmed, schedules simplified. Throws when invalid. */
  function normalize(obj) {
    var r = analyze(obj);
    if (r.problems.length) throw new Error(r.problems.join("; "));
    return r.code;
  }

  /** What the QR code holds: barrier://plan/<payload>. Throws when invalid. */
  function encode(obj) { return LINK_PREFIX + payloadOf(normalize(obj)); }

  // MARK: In words (PlanCode.summary, Engine.describe)

  function every(on, length) {
    if (on.all) return 1;
    if (on.d) return null;
    var n = on.n;
    if (!n.length) return null;
    if (n.length === length) return 1;
    if (length % n.length !== 0) return null;
    var gap = length / n.length;
    for (var i = 1; i < n.length; i++) if (n[i] - n[i - 1] !== gap) return null;
    return gap;
  }

  // MARK: Placing build-ups (AppState.startBuildUp, lineUp, Engine.compact, setEvery, resize)

  function lcm(a, b) {
    function gcd(x, y) { return y === 0 ? x : gcd(y, x % y); }
    return a / gcd(a, b) * b;
  }

  function range(n) { var out = []; for (var i = 0; i < n; i++) out.push(i); return out; }

  // The shortest rotation that keeps every step's pattern.
  function compact(plan) {
    var L = Math.max(1, plan.length);
    if (L <= 1) return plan;
    for (var d = 1; d < L; d++) {
      if (L % d !== 0) continue;
      var ok = plan.steps.every(function (on) {
        if (!on.n) return true;
        return range(L).every(function (i) { return (on.n.indexOf(i) >= 0) === (on.n.indexOf(i % d) >= 0); });
      });
      if (!ok) continue;
      return {
        length: d,
        steps: plan.steps.map(function (on) { return on.n ? { n: on.n.filter(function (x) { return x < d; }) } : on; }),
      };
    }
    return plan;
  }

  function resize(plan, to) {
    var old = Math.max(1, plan.length);
    return {
      length: to,
      steps: plan.steps.map(function (on) {
        return on.n ? { n: range(to).filter(function (i) { return on.n.indexOf(i % old) >= 0; }) } : on;
      }),
    };
  }

  // Each build-up's first stage, in step order, on a fresh phone from day 1: false when one doesn't fit.
  function fits(routine) {
    var plan = {
      length: routine.l || 1,
      steps: routine.s.map(function (s) { return s.n ? { n: s.n } : s.d ? { d: s.d } : { all: true }; }),
    };
    for (var i = 0; i < routine.s.length; i++) {
      var b = routine.s[i].b;
      if (!b) continue;
      var n = b[0][0];
      plan.steps[i] = { all: true };
      plan = compact(plan);
      var want = lcm(Math.max(1, plan.length), n);
      if (want > Limit.rotation) return false;
      if (want !== plan.length) plan = resize(plan, want);
      plan.steps[i] = { n: range(want).filter(function (x) { return x % n === 0; }) };
    }
    return true;
  }

  function everyPhrase(n, word) {
    if (n <= 1) return "Every " + word;
    if (n === 2) return "Every other " + word;
    if (n === 3) return "Every 3rd " + word;
    return "Every " + n + "th " + word;
  }

  function lowered(s) { return s.indexOf("Every ") === 0 ? "e" + s.slice(1) : s; }

  function schedule(step, length, slot) {
    var word = SLOT_WORD[slot];
    if (step.d) {
      var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
      if (step.d.length === 7) return "Every day";
      return step.d.map(function (x) { return names[x]; }).join(", ");
    }
    if (!step.n) return "Every " + word;
    var gap = every({ n: step.n }, length);
    if (gap !== null) {
      if (gap === 1) return "Every " + word;
      if (gap === 2) return "Every other " + word;
      if (gap === 3) return "Every 3rd " + word;
      return "Every " + gap + "th " + word;
    }
    return step.n.length + " of every " + length + " " + word + "s";
  }

  function courseText(days) {
    if (days % 7 === 0) return days === 7 ? "1 week" : days / 7 + " weeks";
    return days === 1 ? "1 day" : days + " days";
  }

  // A build-up in the editor's words (PlanCode.buildUpLines).
  function buildUpLines(stages, word) {
    if (!stages || !stages.length) return [];
    var plan = stages.map(function (st, i) {
      var phrase = everyPhrase(st[0], word);
      return (i === 0 ? phrase : lowered(phrase)) + " for " + courseText(st[1]);
    });
    return [plan.join(", then "), "Tendwell asks how your skin is before each move up"];
  }

  /** The routine in the app's words. Throws when invalid. */
  function describe(obj) {
    var code = normalize(obj);
    var present = SLOTS.filter(function (slot) { return code[slot]; });
    var bodies = present.filter(function (slot) { return BODY[slot]; }).length;
    var sections = present.map(function (slot) {
      var r = code[slot];
      var length = r.l || 1;
      var word = SLOT_WORD[slot];
      return {
        slot: slot,
        // Two body routines go by their moments, as on the Routine tab.
        title: BODY[slot] ? (bodies > 1 && r.q ? r.q : r.n) : SLOT_TITLE[slot],
        rotation: length > 1 ? "Repeats every " + length + " " + word + "s" : null,
        rows: r.s.map(function (step) {
          var p = code.p[step.p];
          var first;
          if (step.b) {
            var goal = every(step.n ? { n: step.n } : { all: true }, length);
            first = everyPhrase(step.b[0][0], word) + ", building up to " + lowered(everyPhrase(goal, word));
          } else {
            first = schedule(step, length, slot);
          }
          if (step.a) first += " · " + step.a;
          var lines = [first].concat(buildUpLines(step.b, word));
          if (step.h) lines.push(step.h);
          if (step.w) lines.push("Then wait " + step.w + " minute" + (step.w === 1 ? "" : "s"));
          if (p.d) lines.push("For " + courseText(p.d));
          return { name: p.n, lines: lines, note: p.o || null };
        }),
      };
    });
    return { clinic: code.c || null, sections: sections, ifIrritated: code.i || null };
  }

  /** The same words as plain text, one line each. */
  function describeText(obj) {
    var d = describe(obj);
    var out = [];
    if (d.clinic) out.push("From " + d.clinic);
    d.sections.forEach(function (s) {
      out.push(s.title + ", in this order");
      if (s.rotation) out.push("  " + s.rotation);
      s.rows.forEach(function (row) {
        out.push("  " + row.name);
        row.lines.forEach(function (l) { out.push("    " + l); });
        if (row.note) out.push("    " + row.note);
      });
    });
    if (d.ifIrritated) out.push("If your skin gets irritated", "  " + d.ifIrritated);
    return out.join("\n");
  }

  // MARK: Examples to edit. Not medical advice. Names, amounts and how-to from Presets.swift.

  var SPF_HOW = "Last step of the morning. Broad-spectrum.";
  var examples = [
    {
      title: "Starting tretinoin",
      code: {
        v: 1,
        p: [
          { n: "Gentle cleanser", k: "cleanser" },
          { n: "Tretinoin", k: "retinoid" },
          { n: "Moisturizer", k: "moisturizer" },
          { n: "Sunscreen SPF 30+", k: "spf" },
        ],
        am: { s: [{ p: 0 }, { p: 2 }, { p: 3, h: SPF_HOW }] },
        pm: {
          s: [
            { p: 0, w: 20 },
            // Starting slowly (Presets.buildUpStages): two weeks every 3rd night, two weeks every other night, then every night.
            { p: 1, a: "Pea-size for the whole face", h: "On completely dry skin", b: [[3, 14], [2, 14]] },
            { p: 2 },
          ],
        },
      },
    },
    {
      title: "Adapalene every other night",
      code: {
        v: 1,
        p: [
          { n: "Gentle cleanser", k: "cleanser" },
          { n: "Adapalene", k: "retinoid" },
          { n: "Benzoyl peroxide", k: "treatment" },
          { n: "Moisturizer", k: "moisturizer" },
          { n: "Sunscreen SPF 30+", k: "spf" },
        ],
        am: { s: [{ p: 0 }, { p: 2, a: "Thin layer on affected areas" }, { p: 3 }, { p: 4, h: SPF_HOW }] },
        pm: { l: 2, s: [{ p: 0 }, { p: 1, a: "Pea-size for the whole face", h: "On completely dry skin", n: [0] }, { p: 3 }] },
      },
    },
    {
      title: "Back treatment",
      code: {
        v: 1,
        p: [{ n: "Benzoyl peroxide wash", k: "treatment" }],
        body: {
          n: "Back",
          q: "After shower",
          s: [{ p: 0, h: "In the shower: leave on a few minutes, then rinse. Follow your label." }],
        },
      },
    },
  ];

  return {
    VERSION: VERSION,
    LINK_PREFIX: LINK_PREFIX,
    Limit: Limit,
    validate: validate,
    normalize: normalize,
    encode: encode,
    describe: describe,
    describeText: describeText,
    examples: examples,
  };
});
