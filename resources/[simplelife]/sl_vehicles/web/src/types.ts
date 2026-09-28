export interface Stats { speed: number; accel: number; braking: number; handling: number }

export interface StockItem {
  model: string; label: string; brand?: string; category: string
  seats?: number; trunk?: number; stats?: Stats
  import: number; price: number; qty: number; display: boolean
}

export interface DealerMeta {
  id: string; label: string; accent: string
  categories: string[]; catNames: Record<string, string>
}

export interface Grade { id: number; name: string; perms: string[]; commission: number; salary: number }
export interface Employee { charid: number; gradeId: number | null; name: string }
export interface Order { id: number; model: string; label: string; qty: number; remaining: number; status: string; priority: boolean; eta: number }
export interface Lead { id: number; name: string; number?: string; subject?: string; message?: string; created: string }
export interface Balances { cash: number; bank: number }

export interface VenteData {
  ok: boolean; dealer: DealerMeta; stock: StockItem[]; perms: string[]
}
export interface GestionData {
  ok: boolean; dealer: DealerMeta; role: string; perms: string[]; permList: string[]
  stock: StockItem[]; employees: Employee[]; grades: Grade[]; till: number
  orders: Order[]; leads: Lead[]; margin: { min: number; max: number }
  import: { normal: number; priority: number; fee: number }
}
export interface BillData {
  billId: number; dealerLabel: string; label: string; brand?: string; model: string; price: number
}
export interface ImpoundVehicle { id: number; plate: string; model: string; label: string; fuel: number; body: number; engine: number }
export interface ImpoundData {
  ok: boolean; lot: { id: string; label: string; accent: string }; vehicles: ImpoundVehicle[]; fee: number; balances: Balances
}

export const PERM_LABELS: Record<string, string> = {
  vente: 'Vente', import: 'Import / convoi', prix: 'Prix', caisse: 'Caisse',
  employes: 'Employés', grades: 'Grades', expo: 'Exposition', leads: 'Demandes',
}
