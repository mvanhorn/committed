/**
 * A count as the notifications write it: "1,204", as the app's counts read. Every kind uses it
 * except passes, whose copy stays byte for byte the shipped `NotificationService.copy(for:)`.
 */
export function formatCount(count: number): string {
  return count.toLocaleString("en-US");
}
