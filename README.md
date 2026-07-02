# LittleGrape (Zemra Ime)

A dating web application for the Albanian community, built with Phoenix LiveView.
Users create a profile, discover and swipe on candidates, form mutual matches,
and chat in real time. The UI is fully internationalized across six locales
(Albanian, English, Italian, Greek, German, French), with Albanian as the
production default.

## Domain overview

The business logic lives in context modules under `lib/little_grape/`:

- **Accounts** — user registration/auth (magic-link + password via
  `phx.gen.auth`, scope-based) and profiles.
- **Discovery** — builds the ranked candidate feed (hard filters plus soft
  compatibility scoring).
- **Swipes** — like/pass actions; a reciprocal like triggers a match.
- **Matches** — mutual matches and their conversations.
- **Messaging** — conversations and messages with real-time delivery over
  Phoenix PubSub.
- **Blocks** — user blocking, enforced across discovery and messaging.

The web layer (`lib/little_grape_web/`) is LiveView-first: `DiscoverLive`,
`MatchesLive`, and `ChatLive`, plus the `phx.gen.auth` controllers.

## Prerequisites

- Elixir `1.20.2` and Erlang/OTP `28.5.0.2` (see `.tool-versions`; `asdf install`
  will pick these up)
- PostgreSQL (a local server reachable with the `config/dev.exs` credentials)

Asset tooling (esbuild and Tailwind) is managed by the `:esbuild` and
`:tailwind` Hex packages, which download standalone binaries — **no Node.js or
npm is required**.

## Setup

```bash
mix setup
```

`mix setup` installs dependencies, creates and migrates the database, seeds it,
and builds assets. Then start the server:

```bash
mix phx.server
# or, inside IEx:
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000).

## Testing and quality gates

```bash
mix test          # full suite (auto-creates and migrates the test DB)
mix precommit     # the full gate set, identical to CI
```

`mix precommit` runs, in order: compile (warnings-as-errors), unused-dep check,
format check, dependency audit (`deps.audit` + `hex.audit`), Sobelow security
analysis, Credo (`--strict`), and tests with coverage (`mix coveralls`).

Individual gates:

```bash
mix format --check-formatted
mix credo --strict
mix sobelow --config .sobelow-conf
mix deps.audit && mix hex.audit
mix coveralls               # coverage; fails below the floor in coveralls.json
mix dialyzer                # type analysis (first run builds the PLT, ~1 min)
```

Coverage is enforced: `mix coveralls` fails if total coverage drops below the
`minimum_coverage` configured in `coveralls.json`.

## Internationalization

Supported locales are defined once in `config/config.exs` under the Gettext
backend's `:allowed_locales`; `LittleGrapeWeb.Plugs.Locale` derives its accepted
set from that key. Translations live in `priv/gettext/<locale>/`. After adding
or changing `gettext(...)` strings, run:

```bash
mix gettext.extract --merge
```

## Deployment (Fly.io review app)

CI is defined in `.github/workflows/elixir.yml`. On every push to `main`, after
the test job passes, the `deploy-review` job deploys a review app to Fly.io:

```bash
flyctl deploy --remote-only --config ./fly.review.toml --dockerfile ./Dockerfile.review
```

The review app (`little-grape-review`, region `yyz`) runs database migrations
via its release command on deploy. Deployment requires the `FLY_API_TOKEN`
repository secret.
