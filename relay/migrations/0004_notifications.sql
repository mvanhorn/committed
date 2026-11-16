-- Relay notifications (spec #124): the relay also sends alert notifications (passes first; close
-- calls, results, records and the streak reminder later) while the iPhone app is closed. An
-- installation now exists while Live rank or relay notifications is on.
--
-- Additive with defaults, so rows from 1.0.x apps (and the Worker that wrote them) read as
-- "Live rank on, no notifications" and nothing changes for anyone until they opt in.

ALTER TABLE installations ADD COLUMN live_rank INTEGER NOT NULL DEFAULT 1;   -- 0 = the cycle never touches a Live Activity
ALTER TABLE installations ADD COLUMN alert_token TEXT;                       -- the ordinary APNs device token (hex) for alert pushes
ALTER TABLE installations ADD COLUMN notifications_json TEXT;                -- notification preferences (JSON); NULL = relay notifications off
ALTER TABLE installations ADD COLUMN rivals_json TEXT NOT NULL DEFAULT '[]'; -- pinned rivals, at most 3, each on the board
-- Per-installation notification state, one JSON object keyed by kind ({"passes": …}), so later
-- kinds extend it without a migration. Never holds tokens.
ALTER TABLE installations ADD COLUMN notification_state TEXT;
