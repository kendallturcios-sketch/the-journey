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
the spiritual gifts survey. A **Your Spiritual Gifts** step is done at home between Levels 2 and 3: they take the
survey and record their top three gifts, and Level 3 stays locked until they do. Level 3 reviews their gifts and records their testimony.
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

## Sending a level to phones

In the facilitator app, every level has a **Send Level N to phones** card with a link, a **Text it**
button (opens the facilitator's own messaging app, nothing is sent from a server), a share sheet,
a copy button and a QR code that can be shown full screen on the projector. The link looks like
`/en/participant/?level=3` and opens that level on the participant's phone. It carries no identity:
progress stays on each person's own phone. Copies of the app on other addresses get the link and
buttons without the QR code (the QR codes are made for ARISE Miami's address).

### Reviewing every level

`/en/participant/?review` (Spanish: `/es/participant/?review`) is for staff walk-throughs. Every level and the
gifts step open, nothing is required (the "About you" fields, feedback questions, name form), and the code
`4827` finishes any level. Nothing is saved on the phone and nothing is sent to Planning Center or the server,
so it can't create a test person or alert anyone, and a phone's real saved name and progress are left alone.
`?preview` still opens every level on any day but sends real submissions.

### Short address

`/go/` opens the app in the visitor's language, and `/go/?level=3` opens a level (the app still asks who they are
first). Point a short address you own (for example `arisemiami.org/journey`) at it.

### Someone on a new phone

Progress is stored on each person's own phone. When someone finished earlier levels on another phone, the
facilitator app shows a daily **let-in code** (third box in the header). Entering it on the participant's
phone marks their earlier levels as done on that phone only. Nothing is sent to Planning Center, it expires
at midnight, and it never skips the day's schedule.

### Home-screen tip

On iPhone and Android the home screen shows a short "add to your home screen" tip, once, until dismissed
or until the app is opened from the home screen.

### Spiritual gifts: staff board and reminder texts

When someone saves their top three gifts, the app tells the server (table `journey_people`, see
`db/019_journey_people.sql`; only the server can read it). Their gifts still go to Planning Center with the
Level 3 form. The staff board lists everyone who finished Level 2 but hasn't saved their gifts.
Reminder texts are **off by default**. Set the `GIFT_REMINDERS` secret to `test` (texts the owner only) and
then `live` (texts people who ticked the optional text-message box, at most twice each, 3 days after
Level 2 and 4 days later). Replying STOP stops them.

## How ARISE Miami runs it

The apps send each finished level to Planning Center through a small Supabase Edge
Function (`supabase/functions/journey-submit`). A daily GitHub Action alerts leaders
about follow-ups, and `board.html` is a passcode-protected staff board. Keys and leader
contacts live only in server secrets, never in this repo.

## License

MIT — use it, change it, share it. Attribution appreciated, not required.
