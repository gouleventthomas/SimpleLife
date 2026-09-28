// Money formatting: 1234 -> "$1,234".
export function money(n: number): string {
  return '$' + Math.round(Number(n) || 0).toLocaleString('en-US')
}
