' asteroidshape.bas -- which of the AST_SHAPES asteroid shapes (#436) an asteroid is.
' The pick is derived from the spin rate the spawner already drew (dry, in [-1, 1)), so a shape costs
' no RNG_GAME draw and a seeded run keeps its layout. Needs AST_SHAPES from dims.bas.
' Local variable prefix: ash

Function AST_ShapeFor%(ashDry As Single)
    Dim ashK As Long
    ashK = Int((ashDry + 1) * 0.5 * 997)
    If ashK < 0 Then ashK = 0
    AST_ShapeFor% = ashK Mod AST_SHAPES
End Function
