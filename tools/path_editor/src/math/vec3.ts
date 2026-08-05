export interface Vec3 {
  x: number
  y: number
  z: number
}

export const v3 = {
  make:  (x: number, y: number, z: number): Vec3 => ({ x, y, z }),
  clone: (v: Vec3): Vec3 => ({ x: v.x, y: v.y, z: v.z }),
  len:   (v: Vec3): number => Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z),
  len2:  (v: Vec3): number => v.x * v.x + v.y * v.y + v.z * v.z,

  norm: (v: Vec3): Vec3 => {
    const l = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) || 1
    return { x: v.x / l, y: v.y / l, z: v.z / l }
  },

  add:   (a: Vec3, b: Vec3): Vec3 => ({ x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }),
  sub:   (a: Vec3, b: Vec3): Vec3 => ({ x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }),
  scale: (v: Vec3, s: number): Vec3 => ({ x: v.x * s, y: v.y * s, z: v.z * s }),
  dot:   (a: Vec3, b: Vec3): number => a.x * b.x + a.y * b.y + a.z * b.z,

  cross: (a: Vec3, b: Vec3): Vec3 => ({
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  }),
}
