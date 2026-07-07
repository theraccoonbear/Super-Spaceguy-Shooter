' Key index constants — pass these to E3D_KeyHeld
Const E3D_KEY_LEFT   = 19200
Const E3D_KEY_RIGHT  = 19712
Const E3D_KEY_UP     = 18432
Const E3D_KEY_DOWN   = 20480
Const E3D_KEY_SPACE  = 32
Const E3D_KEY_W      = 119
Const E3D_KEY_A      = 97
Const E3D_KEY_S      = 115
Const E3D_KEY_D      = 100
Const E3D_KEY_ESCAPE = 27
Const E3D_KEY_TAB    = 9

' Call once per frame before reading input
Sub E3D_InputUpdate (held() As Integer)
    held(E3D_KEY_LEFT)   = Abs(_KeyDown(19200))
    held(E3D_KEY_RIGHT)  = Abs(_KeyDown(19712))
    held(E3D_KEY_UP)     = Abs(_KeyDown(18432))
    held(E3D_KEY_DOWN)   = Abs(_KeyDown(20480))
    held(E3D_KEY_SPACE)  = Abs(_KeyDown(32))
    held(E3D_KEY_W)      = Abs(_KeyDown(119))
    held(E3D_KEY_A)      = Abs(_KeyDown(97))
    held(E3D_KEY_S)      = Abs(_KeyDown(115))
    held(E3D_KEY_D)      = Abs(_KeyDown(100))
    held(E3D_KEY_ESCAPE) = Abs(_KeyDown(27))
    held(E3D_KEY_TAB)    = Abs(_KeyDown(9))
End Sub
