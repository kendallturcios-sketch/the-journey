# The Journey — a discipleship app

Built for ARISE Miami SDA Church. **Free for any church to copy and adapt.**

**Open it here:** https://kendallturcios-sketch.github.io/the-journey/

## What it is

A four-level discipleship track, one Sabbath per level, taught monthly — twelve full cycles a year.

| Level | Sabbath | Theme |
|---|---|---|
| 1 | First | Discover Your Purpose |
| 2 | Second | Discover the Method |
| 3 | Third | Discover Your Giftedness |
| 4 | Fourth | Discover Your Impact |

Participants follow along on their phones during the live session, filling in the
worksheet as it's taught. Level 1 ends with a baptism invitation. Level 2 assigns
the spiritual gifts survey. Level 3 records their gifts and their testimony.
Level 4 is the covenant and choosing a ministry.

## Four apps

| | English | Español |
|---|---|---|
| Participants | [`/en/participant/`](en/participant/) | [`/es/participant/`](es/participant/) |
| Facilitators | [`/en/facilitator/`](en/facilitator/) | [`/es/facilitator/`](es/facilitator/) |

The facilitator version shows every answer, plus the discussion prompts, transitions
and group instructions from the leader guides.

## Making it yours

Click **Fork** at the top of this page. Everything is plain text near the top of each
HTML file — church name, lessons, ministries, leaders, session code. No build step, no
dependencies, no server. Open the file in a browser and it runs.

Scripture is **Berean Standard Bible** (English) and **Reina-Valera 1909** (Spanish),
both public domain — nothing to license, and it works with no internet connection.

## Running it for real

The `db` folder holds a Postgres schema (works on Supabase) for the full version:
accounts, saved progress, attendance, automatic notification of ministry leaders when
someone signs up to serve, and progress synced back to Planning Center.

Level gating is enforced in the database, not the browser.

`db/leaders.example.sql` shows where contact details go. Keep your real copy out of
version control.

## A note on the demo

Session code is `4827`. Nothing saves across a page refresh. Answering the worksheet
questions is optional so people can look around quickly — in the real version they're required.

## License

MIT — use it, change it, share it. Attribution appreciated, not required.
