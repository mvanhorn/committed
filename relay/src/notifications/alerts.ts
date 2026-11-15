import { isDeadToken, type AlertPayload } from "../apns";
import type { InstallationRow } from "../db";
import type { NotificationDeps } from "./index";

/**
 * Sends one alert notification to the installation's alert token. A token APNs rejects for good is
 * cleared (as the Live Activity tokens are) and logged; `row.alert_token` becomes null so the rest
 * of this run sends nothing more. Returns true on success.
 */
export async function sendAlert(
  row: InstallationRow,
  payload: AlertPayload,
  deps: NotificationDeps,
  options: { collapseId?: string; priority?: 5 | 10 } = {},
): Promise<boolean> {
  const token = row.alert_token;
  if (!token) return false;
  const result = await deps.apns.send({
    pushType: "alert",
    token,
    environment: row.apns_environment,
    priority: options.priority ?? 10,
    payload,
    collapseId: options.collapseId,
  });
  const fields = { id: row.id, kind: payload.kind, status: result.status, reason: result.reason ?? null };
  if (result.status === 200) {
    deps.log("alert_sent", fields);
    return true;
  }
  deps.log("alert_failed", fields);
  if (isDeadToken(result)) {
    row.alert_token = null;
    await deps.store.clearAlertToken(row.id, token);
    deps.log("token_cleared", { id: row.id, token: "alert" });
  }
  return false;
}
