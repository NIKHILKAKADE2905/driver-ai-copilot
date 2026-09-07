# AI Co-Pilot — MVP contract

This is a **driver aid**, not a certified safety system. The driver remains responsible for the vehicle.

## Device and setup

- Android phone mounted on the dash, camera aimed at the **driver’s face**.
- Monitoring is designed for a single driver in frame.

## What must always work

- Local alarm + a short spoken instruction on MODERATE or STRONG drowsiness, **even if the internet or backend is down**.
- Face video **never leaves the phone**.

## What the cloud is for

- Conversational co-pilot (speech / LLM).
- Rest-stop / fuel search along the route (Google Routes + Places).
- API keys (`GROQ_API_KEY`, `MAPS_API_KEY`) live only in server environment variables, never in the Flutter app.

## Out of scope for this MVP

- iOS, accounts, payments, fleet dashboards, medical or regulatory certification.

## Secrets

If this repository was shared, rotate Groq and Google Maps keys and put the new values only in `.env` (gitignored).
