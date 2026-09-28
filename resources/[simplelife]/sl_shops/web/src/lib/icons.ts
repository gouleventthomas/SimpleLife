import { Utensils, CupSoda, Pill, Wrench, FileText, Key, Package, Box, type LucideIcon } from 'lucide-react'

// Item category -> lucide icon (mirrors sl_inventory's grid icons; items have no per-item art).
const CAT: Record<string, LucideIcon> = {
  food: Utensils,
  drink: CupSoda,
  medical: Pill,
  tool: Wrench,
  document: FileText,
  key: Key,
  material: Package,
  misc: Box,
}

export function catIcon(category?: string): LucideIcon {
  return CAT[category || ''] ?? Box
}
