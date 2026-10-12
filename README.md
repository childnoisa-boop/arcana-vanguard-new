# Vanguard Card Collection — Netlify + Supabase

Vanilla HTML/CSS/JavaScript card catalog and collection app. The hosted configuration uses Supabase Auth, Postgres, RLS, and Storage; Netlify serves the static site. There are **no simulator or gameplay features**.

## Shared vs private data

- **Shared:** product/card catalog, Banlist rules, active PR craft recipes, decks only when the owner shares them.
- **Private to the signed-in account:** opened-pack history, Pity/counters, pull collection, saved decks unless individually shared, and craft history/materials.
- Supabase RLS enforces these boundaries. All authenticated users can edit the shared catalog and Banlist. Card images go into the public `card-art` bucket; do not upload images that should remain private.
- Local preview mode stores sample content in that browser only; it is not a multi-user cloud deployment.

## Files

- `index.html` — app UI and client-side features.
- `cloud.js` — Supabase Auth, catalog, collection, deck, Banlist, feed, and PR crafting adapter.
- `scripts/build.mjs` — creates `dist/`, copies static files, and writes a build-time `config.js`.
- `supabase/migrations/20261002000000_initial_schema.sql` — schema, RPCs, RLS, and Storage policies for a new Supabase project.
- `supabase/SCHEMA.md` — table and policy overview.
- `SUPABASE_NETLIFY_SETUP_TH.md` — detailed Thai setup guide for Supabase and Netlify.

## 1. Create and configure Supabase

1. Create a Supabase project and keep its **Project URL** and browser-safe **publishable key** available. Supabase's current publishable keys typically start with `sb_publishable_`. Never use or expose a `service_role` / secret key in this frontend.
2. **Do not apply the migration remotely yet.** It is marked `DRAFT ONLY` and has only been syntax-parsed here, not run on a local Supabase stack. First test it with the [Supabase CLI and Docker](https://supabase.com/docs/guides/local-development/database-migrations) using `supabase start` and `supabase db reset` in a separate local test project. Only after that test passes, apply it once to a new remote Supabase project. Do not run it on a database with existing tables/data.
3. In **Authentication → URL Configuration**, set the Site URL to the final Netlify URL and allow the matching redirect (for example `https://YOUR-SITE.netlify.app/**`). Update this if you later use a custom domain.
4. Email confirmation can remain enabled. New users may need to confirm their email before signing in.

## 2. Deploy to Netlify

1. Put this folder in a Git repository and connect that repository to Netlify.
2. Use build command `npm run build` and publish directory `dist` (both are set in `netlify.toml`).
3. Add these **build-time** Site environment variables in Netlify:
   - `SUPABASE_URL` — Supabase Project URL.
   - `SUPABASE_ANON_KEY` — paste the project's public **publishable key** (typically `sb_publishable_...`) here. The variable name is kept as `SUPABASE_ANON_KEY` because this app's build script expects that name.
4. Trigger a fresh deploy after setting or changing either variable. `scripts/build.mjs` injects their values into generated `dist/config.js`; Netlify must build again for changes to take effect.

The publishable key is expected to be visible to browsers. **RLS—not secrecy of the publishable key—protects user data.** Do not set, inject, commit, or expose `SUPABASE_SERVICE_ROLE_KEY` or a `sb_secret_...` key in this app.

## 3. Build locally

```sh
npm run build
```

For a cloud-configured local build, provide `SUPABASE_URL` and `SUPABASE_ANON_KEY` to the build process. If either is missing, the build still succeeds in preview mode and the app warns that data is stored only in the current browser. The generated `dist/` folder is the deployable artifact.

## Current deployment status

This repository folder has not been connected to a Supabase project or Netlify account from this session. The SQL file is a migration draft for a new project; the build can be verified locally, but a live login or cross-account RLS test requires the user's Supabase project and Netlify environment variables.
