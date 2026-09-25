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

Click **Fork** at the top of this page. That makes your own copy under your GitHub
account. Nothing you change in your fork affects ARISE Miami's app. If you improve
something you'd like to share back, open a pull request; ARISE reviews it before
anything changes here.

Everything is plain text near the top of each HTML file: church name, lessons,
ministries, schedule. No build step, no dependencies. Open the file in a browser and it runs.

- **Your copy sends nothing to ARISE's Planning Center.** Sending only works from
  ARISE Miami's own site. To record answers in your own Planning Center, deploy your own
  copy of `supabase/functions/journey-submit` with your own keys, then point
  `SUBMIT_URL` in the participant apps at it.
- **Codes:** the facilitator app shows a daily session code and make-up code per level.
  Add `?preview` to the participant app's address to open every level on any day.
- **Please keep** `about.html` and the credit line at the bottom of the app:
  *The Journey © ARISE Miami SDA Church · used by permission.*

Scripture is **Berean Standard Bible** (English) and **Reina-Valera 1909** (Spanish),
both public domain — nothing to license, and it works with no internet connection.

## How ARISE Miami runs it

The apps send each finished level to Planning Center through a small Supabase Edge
Function (`supabase/functions/journey-submit`). A daily GitHub Action alerts leaders
about follow-ups, and `board.html` is a passcode-protected staff board. Keys and leader
contacts live only in server secrets, never in this repo.

## License

MIT — use it, change it, share it. Attribution appreciated, not required.
