import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export const money = (n: number) =>
  '$' + Math.floor(n || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
