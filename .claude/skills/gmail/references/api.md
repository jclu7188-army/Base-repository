# Gmail API v1 reference

Base: `https://gmail.googleapis.com/gmail/v1/users/me` (`me` = the authenticated user).
Auth: `Authorization: Bearer <token>`. Scopes, least to most privileged:

| Scope                                              | Allows                                  |
|----------------------------------------------------|-----------------------------------------|
| `https://www.googleapis.com/auth/gmail.readonly`   | read messages, threads, labels, settings|
| `https://www.googleapis.com/auth/gmail.send`       | send only (no read)                     |
| `https://www.googleapis.com/auth/gmail.compose`    | create/read/send drafts, send           |
| `https://www.googleapis.com/auth/gmail.labels`     | manage labels                           |
| `https://www.googleapis.com/auth/gmail.modify`     | everything except permanent delete      |
| `https://mail.google.com/`                         | everything, incl. permanent delete      |

## Table of contents

- Messages
- Message payload (MIME tree)
- Threads
- Drafts
- Labels
- Attachments
- History (incremental sync)
- Settings: filters, vacation, signatures
- Batch requests
- Search operators
- Building RFC 2822 messages

## Messages

| Method | Path | Notes |
|--------|------|-------|
| GET | `/messages?q=&maxResults=&pageToken=&labelIds=&includeSpamTrash=` | Returns `{messages:[{id,threadId}], nextPageToken, resultSizeEstimate}`. IDs only — follow with `messages.get`. `labelIds` may repeat. |
| GET | `/messages/{id}?format=full\|metadata\|minimal\|raw&metadataHeaders=Subject&metadataHeaders=From` | `full` = parsed MIME tree; `metadata` = headers only (cheap); `raw` = base64url RFC 2822 in `raw`. |
| POST | `/messages/send` | Body `{raw, threadId?}`. Returns `{id, threadId, labelIds}`. |
| POST | `/messages/{id}/modify` | `{addLabelIds:[], removeLabelIds:[]}`. |
| POST | `/messages/batchModify` | `{ids:[…≤1000], addLabelIds, removeLabelIds}`. Returns 204. |
| POST | `/messages/{id}/trash` · `/untrash` | |
| DELETE | `/messages/{id}` | Permanent. Requires `https://mail.google.com/`. Avoid. |
| POST | `/messages/import` · `/messages` (insert) | Inject a message without sending (migration use). |

Useful message fields: `id`, `threadId`, `labelIds`, `snippet`, `historyId`, `internalDate`
(epoch ms as string), `sizeEstimate`, `payload`.

## Message payload (MIME tree)

```
payload
├─ mimeType            e.g. multipart/alternative, text/plain, multipart/mixed
├─ headers[]           {name, value} — From, To, Cc, Subject, Date, Message-ID, In-Reply-To, References
├─ body {size, data?, attachmentId?}
└─ parts[]             recursive: same shape as payload
```

- Text is in `body.data` as **base64url** (`-_` alphabet, often unpadded). Decode with
  `tr '_-' '/+' | base64 -d` after re-adding `=` padding to a multiple of 4.
- A simple message: `payload.mimeType = text/plain`, body inline.
- HTML + text: `multipart/alternative` with two parts.
- Attachments: `multipart/mixed`; the attachment part has `filename` and
  `body.attachmentId` (no `data`) — fetch separately.
- Inline images: `multipart/related`, part header `Content-ID`.

jq to pull the first text/plain body out of any depth:

```bash
jq -r '[.. | objects | select(.mimeType? == "text/plain" and .body.data?) | .body.data][0]'
```

## Threads

| Method | Path | Notes |
|--------|------|-------|
| GET | `/threads?q=&maxResults=&pageToken=&labelIds=` | `{threads:[{id, snippet, historyId}], nextPageToken}` |
| GET | `/threads/{id}?format=full\|metadata\|minimal` | `messages[]` oldest → newest, each a full message object |
| POST | `/threads/{id}/modify` · `/trash` · `/untrash` | Applies to every message in the thread |
| DELETE | `/threads/{id}` | Permanent. Avoid. |

## Drafts

| Method | Path | Notes |
|--------|------|-------|
| GET | `/drafts?maxResults=&pageToken=&q=` | `{drafts:[{id, message:{id, threadId}}]}` |
| GET | `/drafts/{id}?format=` | |
| POST | `/drafts` | `{message:{raw, threadId?}}` |
| PUT | `/drafts/{id}` | Replace with `{message:{raw}}` |
| POST | `/drafts/send` | `{id}` — sends and deletes the draft |
| DELETE | `/drafts/{id}` | |

## Labels

| Method | Path | Notes |
|--------|------|-------|
| GET | `/labels` | `{labels:[{id, name, type: system\|user, messageListVisibility, labelListVisibility}]}` |
| GET | `/labels/{id}` | Adds `messagesTotal`, `messagesUnread`, `threadsTotal`, `threadsUnread` |
| POST | `/labels` | `{name:"Clients/Acme", labelListVisibility:"labelShow", messageListVisibility:"show", color:{backgroundColor, textColor}}` — `/` nests |
| PATCH | `/labels/{id}` | rename, colour |
| DELETE | `/labels/{id}` | User labels only |

System label IDs: `INBOX`, `UNREAD`, `STARRED`, `IMPORTANT`, `SENT`, `DRAFT`, `SPAM`, `TRASH`,
`CHAT`, `CATEGORY_PERSONAL`, `CATEGORY_SOCIAL`, `CATEGORY_PROMOTIONS`, `CATEGORY_UPDATES`,
`CATEGORY_FORUMS`. User label IDs look like `Label_1234567890`.

## Attachments

```
GET /messages/{messageId}/attachments/{attachmentId}   → {size, data}   (base64url)
```

```bash
gmail ".../messages/MSG/attachments/ATT" | jq -r .data | tr '_-' '/+' | base64 -d > file.pdf
```

Attachments up to 25 MB when sending; larger files should be shared via Drive links.

## History (incremental sync)

```
GET /history?startHistoryId=&historyTypes=messageAdded&labelId=INBOX&pageToken=
```

Returns `history[]` entries with `messagesAdded`, `messagesDeleted`, `labelsAdded`,
`labelsRemoved`. Store the `historyId` from the last full sync; a `404` means the id is too old —
do a full resync. Push notifications: `POST /watch` with a Pub/Sub topic.

## Settings

| Path | Purpose |
|------|---------|
| `/settings/filters` (GET/POST/DELETE) | `{criteria:{from, to, subject, query, hasAttachment}, action:{addLabelIds, removeLabelIds, forward}}` |
| `/settings/vacation` (GET/PUT) | auto-reply: `{enableAutoReply, responseSubject, responseBodyPlainText, startTime, endTime}` (epoch ms) |
| `/settings/sendAs` (GET) | aliases and signatures; `PATCH /settings/sendAs/{email}` `{signature}` |
| `/settings/forwardingAddresses`, `/settings/imap`, `/settings/pop`, `/settings/language`, `/settings/autoForwarding` | |

## Batch requests

Up to 100 sub-requests in one `multipart/mixed` POST to
`https://gmail.googleapis.com/batch/gmail/v1`. Each part is `Content-Type: application/http`
followed by a raw HTTP request line and headers. Useful for `messages.get` fan-out after a
search; the bundled scripts use sequential calls for simplicity — switch to batch if a search
returns hundreds of hits.

## Search operators (`q`)

Identical to the Gmail search box.

| Category | Operators |
|----------|-----------|
| People | `from:`, `to:`, `cc:`, `bcc:`, `deliveredto:`, `list:` |
| Time | `after:YYYY/MM/DD`, `before:`, `newer:`, `older:`, `newer_than:7d`, `older_than:1y` (units `d`, `m`, `y`) |
| Content | `subject:`, `"exact phrase"`, `+exactword`, `filename:pdf`, `has:attachment`, `has:drive`, `has:document`, `has:spreadsheet`, `has:youtube`, `AROUND 5` |
| Place | `in:inbox`, `in:sent`, `in:draft`, `in:trash`, `in:spam`, `in:anywhere`, `in:archive`, `label:NAME`, `category:primary\|social\|promotions\|updates\|forums` |
| State | `is:unread`, `is:read`, `is:starred`, `is:important`, `is:snoozed`, `is:muted`, `has:userlabels`, `has:nouserlabels` |
| Size | `larger:10M`, `smaller:500K`, `size:` |
| Logic | space = AND, `OR`, `{a b}` = OR, `-term` = NOT, `( )` grouping |

Tips: prefer a few distinctive keywords over long phrases; combine `from:` with `newer_than:`
to keep result sets small; `label:` accepts names in the REST `q` (the connector tool wants
IDs).

## Building RFC 2822 messages

Minimum headers: `To`, `Subject`, `Content-Type`. Gmail fills `From`, `Date`, `Message-ID`.
Lines end with `\r\n`; a blank line separates headers from body. Then base64url-encode the whole
thing (`base64 -w0 | tr '/+' '_-' | tr -d '='`).

Multipart with an attachment:

```
To: alice@example.com
Subject: Report
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="b1"

--b1
Content-Type: text/plain; charset=UTF-8

Attached.
--b1
Content-Type: application/pdf; name="report.pdf"
Content-Disposition: attachment; filename="report.pdf"
Content-Transfer-Encoding: base64

<base64 of the file, wrapped at 76 chars>
--b1--
```

HTML + plain alternative: `multipart/alternative` with the `text/plain` part first.

Reply headers: `In-Reply-To: <id@host>` and `References: <id@host>` copied from the original's
`Message-ID` header (angle brackets included), subject `Re: <original>`, and `threadId` in the
JSON body so Gmail threads it.

Non-ASCII subjects: encode as `=?UTF-8?B?<base64>?=`.
