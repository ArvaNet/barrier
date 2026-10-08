# Web prototype (not used by the iPhone app)

The first version of Barrier, built as an installable web app before the
decision to go native. Kept for a possible Android or web version:

- `src/lib/engine.ts`: the schedule engine in TypeScript (same rules as
  `Packages/BarrierCore`), with tests in `test/app`.
- `worker/`: a Cloudflare Worker that stores each device's upcoming reminders
  and sends them as Web Push (RFC 8291 encryption + VAPID, tested against the
  RFC test vectors in `test/worker`).

`npm install && npm test` runs the tests.
