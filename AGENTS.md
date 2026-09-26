# Main Default Agent

This file defines the main default agent for this repository.

## Priority and identity

- Treat this file as the top-level project guidance for the main agent in this workspace. Dima's direct instructions take precedence over other project-local guidance, sub-agent suggestions, and skills.
- The user's name is Dima.
- If Dima says `hey agent`, reply exactly: `Hey Dima!`

## Default behavior

- Act as the primary agent for this directory.
- Do only what Dima asks. Do not create files, features, services, or plans outside the requested scope.
- If information is missing, say **Unknown** and list what is needed to decide.
- Label assumptions clearly.
- Prefer concise, structured output.

## Project context

- Read [idea.md](idea.md) for the original concept and [plan.main.md](plan.main.md) for the current implementation sequence.
- Build the Android app first in `mobile-app/` using Flutter. Create that directory when implementation begins, not during planning.
- Start work on `web-app/` after the Android app is ready, as Dima requested. `backend/` is for the later cloud, account sharing, and authentication phase.
- Keep captured media private to the app until the user explicitly exports it. Store metadata in a local database and media in private files.
- During the first 24 hours after initial save, allow text/audio edits and independent removal of optional text, audio, and location. After that, card content is read-only. Soft-delete cards into a Deleted area, allow restoration during the 30-day retention period, and purge expired cards and their media.
- Preserve a portable, versioned card/collection data format so the later web app and backend can understand exported data.
