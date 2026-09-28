# ============================================================
#  Auto Clicker - application Windows simple et rapide
#  Lance-la avec : double-clic sur AutoClicker.bat
# ------------------------------------------------------------
#  - Choix du clic : gauche / droit / milieu
#  - Delai entre clics (ms) + Maintien du clic (ms)
#  - Raccourci clavier pour activer / desactiver (marche en arriere-plan)
#  - Demarre en ADMINISTRATEUR automatiquement
#  - Deux methodes de clic :
#      * Normal (rapide)     -> SendInput  (Bureau, applis, jeux 2D / fenetres)
#      * Jeu (Interception)  -> pilote Interception : simule une VRAIE souris,
#                               fonctionne dans les jeux qui ignorent SendInput.
#  - "Maintien du clic" : duree pendant laquelle le bouton reste enfonce.
#    Indispensable pour les jeux qui lisent la souris image par image
#    (un clic trop bref passe inapercu). Pour un jeu, essaie 50-100 ms.
# ============================================================

# ----------------- Elevation automatique en administrateur -----------------
$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $exe     = (Get-Process -Id $PID).Path
        $argline = "-NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File `"$PSCommandPath`""
        Start-Process -FilePath $exe -Verb RunAs -ArgumentList $argline
        exit
    }
    catch { }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----------------- Fonctions natives -----------------
$code = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
namespace ACK {
  public static class Native {
    // ---------- Mode normal : SendInput ----------
    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public MOUSEINPUT mi; }
    [DllImport("user32.dll", SetLastError=true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    public static void SendInputClick(uint down, uint up, int holdMs) {
      INPUT[] a = new INPUT[1];
      a[0].type = 0; a[0].mi.dwFlags = down; SendInput(1u, a, Marshal.SizeOf(typeof(INPUT)));
      if (holdMs > 0) Thread.Sleep(holdMs);
      a[0].mi.dwFlags = up; SendInput(1u, a, Marshal.SizeOf(typeof(INPUT)));
    }

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SetDllDirectory(string lpPathName);

    // ---------- Mode jeu : Interception ----------
    [StructLayout(LayoutKind.Sequential)]
    public struct MouseStroke { public ushort state; public ushort flags; public short rolling; public int x; public int y; public uint information; }
    [DllImport("interception.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr interception_create_context();
    [DllImport("interception.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void interception_destroy_context(IntPtr context);
    [DllImport("interception.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int interception_send(IntPtr context, int device, ref MouseStroke stroke, uint nstroke);

    public static IntPtr ctx = IntPtr.Zero;

    public static bool InterceptionInit() {
      try { ctx = interception_create_context(); } catch { ctx = IntPtr.Zero; }
      return ctx != IntPtr.Zero;
    }
    // Renvoie le 1er appareil souris (11..20) qui accepte l'injection, 0 sinon. Ne clique pas.
    public static int InterceptionProbe() {
      if (ctx == IntPtr.Zero) return 0;
      MouseStroke s = new MouseStroke();
      for (int d = 11; d <= 20; d++) {
        if (interception_send(ctx, d, ref s, 1u) != 0) return d;
      }
      return 0;
    }
    // Clic complet (appui, maintien holdMs, relache). Renvoie 1 si injecte, 0 sinon.
    public static int InterceptionClick(int device, ushort down, ushort up, int holdMs) {
      if (ctx == IntPtr.Zero) return 0;
      int dev = device;
      MouseStroke s = new MouseStroke();
      s.state = down;
      int r = interception_send(ctx, dev, ref s, 1u);
      if (r == 0) { // appareil choisi muet -> on cherche le bon
        for (int d = 11; d <= 20; d++) { s.state = down; r = interception_send(ctx, d, ref s, 1u); if (r != 0) { dev = d; break; } }
      }
      if (r == 0) return 0;
      if (holdMs > 0) Thread.Sleep(holdMs);
      s.state = up; interception_send(ctx, dev, ref s, 1u);
      return r;
    }
    public static void InterceptionShutdown() {
      if (ctx != IntPtr.Zero) { interception_destroy_context(ctx); ctx = IntPtr.Zero; }
    }
  }
}
'@
Add-Type -TypeDefinition $code

[void][ACK.Native]::SetDllDirectory($PSScriptRoot)
$script:ItcDllOk = [ACK.Native]::InterceptionInit()

$MOUSE = @{
    Gauche = @{ Down = 0x0002; Up = 0x0004; ItcDown = 0x001; ItcUp = 0x002 }
    Droit  = @{ Down = 0x0008; Up = 0x0010; ItcDown = 0x004; ItcUp = 0x008 }
    Milieu = @{ Down = 0x0020; Up = 0x0040; ItcDown = 0x010; ItcUp = 0x020 }
}
$KEYS = [ordered]@{
    'F1' = 0x70; 'F2' = 0x71; 'F3' = 0x72; 'F4' = 0x73; 'F5' = 0x74; 'F6' = 0x75
    'F7' = 0x76; 'F8' = 0x77; 'F9' = 0x78; 'F10' = 0x79; 'F11' = 0x7A; 'F12' = 0x7B
    'Arret defil' = 0x91; 'Pause' = 0x13; 'Inser' = 0x2D; 'Suppr' = 0x2E
    'Origine' = 0x24; 'Fin' = 0x23; 'PgPrec' = 0x21; 'PgSuiv' = 0x22
    'Pave num 0' = 0x60; 'Pave num 1' = 0x61; 'Pave num 2' = 0x62; 'Pave num 3' = 0x63
    'Pave num 4' = 0x64; 'Pave num *' = 0x6A; 'Pave num -' = 0x6D; 'Pave num +' = 0x6B
}

$script:Actif      = $false
$script:ToucheDown = $false

[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================== Fenetre ==============================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Auto Clicker'
$form.Size = New-Object System.Drawing.Size(335, 415)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = 'Type de clic'; $grp.Location = New-Object System.Drawing.Point(15, 6); $grp.Size = New-Object System.Drawing.Size(295, 50)
$rbGauche = New-Object System.Windows.Forms.RadioButton
$rbGauche.Text = 'Gauche'; $rbGauche.AutoSize = $true; $rbGauche.Checked = $true; $rbGauche.Location = New-Object System.Drawing.Point(15, 19)
$rbDroit = New-Object System.Windows.Forms.RadioButton
$rbDroit.Text = 'Droit'; $rbDroit.AutoSize = $true; $rbDroit.Location = New-Object System.Drawing.Point(120, 19)
$rbMilieu = New-Object System.Windows.Forms.RadioButton
$rbMilieu.Text = 'Milieu'; $rbMilieu.AutoSize = $true; $rbMilieu.Location = New-Object System.Drawing.Point(205, 19)
$grp.Controls.AddRange(@($rbGauche, $rbDroit, $rbMilieu))

$grpM = New-Object System.Windows.Forms.GroupBox
$grpM.Text = 'Methode de clic'; $grpM.Location = New-Object System.Drawing.Point(15, 60); $grpM.Size = New-Object System.Drawing.Size(295, 50)
$rbNormal = New-Object System.Windows.Forms.RadioButton
$rbNormal.Text = 'Normal (rapide)'; $rbNormal.AutoSize = $true; $rbNormal.Checked = $true; $rbNormal.Location = New-Object System.Drawing.Point(15, 19)
$rbJeu = New-Object System.Windows.Forms.RadioButton
$rbJeu.Text = 'Jeu (Interception)'; $rbJeu.AutoSize = $true; $rbJeu.Location = New-Object System.Drawing.Point(150, 19)
$grpM.Controls.AddRange(@($rbNormal, $rbJeu))

$lblDelai = New-Object System.Windows.Forms.Label
$lblDelai.Text = 'Delai entre clics (ms) :'; $lblDelai.AutoSize = $true; $lblDelai.Location = New-Object System.Drawing.Point(15, 122)
$numDelai = New-Object System.Windows.Forms.NumericUpDown
$numDelai.Location = New-Object System.Drawing.Point(195, 120); $numDelai.Size = New-Object System.Drawing.Size(115, 22)
$numDelai.Minimum = 1; $numDelai.Maximum = 600000; $numDelai.Value = 100; $numDelai.Increment = 10

$lblHold = New-Object System.Windows.Forms.Label
$lblHold.Text = 'Maintien du clic (ms) :'; $lblHold.AutoSize = $true; $lblHold.Location = New-Object System.Drawing.Point(15, 150)
$numHold = New-Object System.Windows.Forms.NumericUpDown
$numHold.Location = New-Object System.Drawing.Point(195, 148); $numHold.Size = New-Object System.Drawing.Size(115, 22)
$numHold.Minimum = 0; $numHold.Maximum = 1000; $numHold.Value = 50; $numHold.Increment = 10

$lblTouche = New-Object System.Windows.Forms.Label
$lblTouche.Text = 'Raccourci marche/arret :'; $lblTouche.AutoSize = $true; $lblTouche.Location = New-Object System.Drawing.Point(15, 178)
$cmbTouche = New-Object System.Windows.Forms.ComboBox
$cmbTouche.Location = New-Object System.Drawing.Point(195, 175); $cmbTouche.Size = New-Object System.Drawing.Size(115, 22); $cmbTouche.DropDownStyle = 'DropDownList'
$KEYS.Keys | ForEach-Object { [void]$cmbTouche.Items.Add($_) }
$cmbTouche.SelectedItem = 'F6'

$lblDevice = New-Object System.Windows.Forms.Label
$lblDevice.Text = 'Souris (mode jeu) :'; $lblDevice.AutoSize = $true; $lblDevice.Location = New-Object System.Drawing.Point(15, 206)
$numDevice = New-Object System.Windows.Forms.NumericUpDown
$numDevice.Location = New-Object System.Drawing.Point(195, 204); $numDevice.Size = New-Object System.Drawing.Size(115, 22)
$numDevice.Minimum = 11; $numDevice.Maximum = 20; $numDevice.Value = 11

$btn = New-Object System.Windows.Forms.Button
$btn.Location = New-Object System.Drawing.Point(15, 234); $btn.Size = New-Object System.Drawing.Size(295, 40)
$btn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

$lblStatut = New-Object System.Windows.Forms.Label
$lblStatut.Location = New-Object System.Drawing.Point(15, 280); $lblStatut.Size = New-Object System.Drawing.Size(295, 26); $lblStatut.TextAlign = 'MiddleCenter'
$lblStatut.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = 'Le raccourci marche meme fenetre en arriere-plan.'; $lblInfo.Location = New-Object System.Drawing.Point(15, 308); $lblInfo.Size = New-Object System.Drawing.Size(300, 16)
$lblInfo.TextAlign = 'MiddleCenter'; $lblInfo.ForeColor = [System.Drawing.Color]::Gray; $lblInfo.Font = New-Object System.Drawing.Font('Segoe UI', 8)

$estAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$lblAdmin = New-Object System.Windows.Forms.Label
$lblAdmin.Location = New-Object System.Drawing.Point(15, 326); $lblAdmin.Size = New-Object System.Drawing.Size(300, 16); $lblAdmin.TextAlign = 'MiddleCenter'
$lblAdmin.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
if ($estAdmin) { $lblAdmin.Text = 'Mode administrateur : OUI'; $lblAdmin.ForeColor = [System.Drawing.Color]::ForestGreen }
else           { $lblAdmin.Text = 'Mode administrateur : NON'; $lblAdmin.ForeColor = [System.Drawing.Color]::DarkOrange }

$lblItc = New-Object System.Windows.Forms.Label
$lblItc.Location = New-Object System.Drawing.Point(15, 344); $lblItc.Size = New-Object System.Drawing.Size(300, 16); $lblItc.TextAlign = 'MiddleCenter'
$lblItc.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)

$form.Controls.AddRange(@($grp, $grpM, $lblDelai, $numDelai, $lblHold, $numHold, $lblTouche, $cmbTouche, $lblDevice, $numDevice, $btn, $lblStatut, $lblInfo, $lblAdmin, $lblItc))

# ============================== Logique ==============================
function Get-ClickFlags {
    if ($rbDroit.Checked)  { return $MOUSE.Droit }
    if ($rbMilieu.Checked) { return $MOUSE.Milieu }
    return $MOUSE.Gauche
}
function Get-SelectedVK { return [int]$KEYS[[string]$cmbTouche.SelectedItem] }

function Update-ItcStatus {
    if (-not $script:ItcDllOk) {
        $lblItc.Text = 'Interception : DLL introuvable'; $lblItc.ForeColor = [System.Drawing.Color]::Firebrick; return 0
    }
    $dev = [ACK.Native]::InterceptionProbe()
    if ($dev -gt 0) {
        $lblItc.Text = "Interception : pilote ACTIF (souris $dev)"; $lblItc.ForeColor = [System.Drawing.Color]::ForestGreen
        if ($numDevice.Value -lt 11) { $numDevice.Value = $dev }
    }
    else { $lblItc.Text = 'Interception : pilote inactif (redemarre le PC)'; $lblItc.ForeColor = [System.Drawing.Color]::DarkOrange }
    return $dev
}

function Set-Actif {
    param([bool]$on)
    if ($on -and $rbJeu.Checked) {
        $dev = Update-ItcStatus
        if ($dev -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Le pilote Interception n'est pas actif.`n`nRedemarre le PC puis reessaie.", 'Auto Clicker - mode Jeu', 'OK', 'Warning') | Out-Null
            return
        }
    }
    $script:Actif = $on
    if ($on) {
        $script:clickTimer.Interval = [int]$numDelai.Value
        $script:clickTimer.Start()
        $lblStatut.Text = '* ACTIF *'; $lblStatut.ForeColor = [System.Drawing.Color]::ForestGreen
        $btn.Text = "ARRETER  ($($cmbTouche.SelectedItem))"
    }
    else {
        $script:clickTimer.Stop()
        $lblStatut.Text = 'Arrete'; $lblStatut.ForeColor = [System.Drawing.Color]::Firebrick
        $btn.Text = "DEMARRER  ($($cmbTouche.SelectedItem))"
    }
}

$script:clickTimer = New-Object System.Windows.Forms.Timer
$script:clickTimer.Interval = 100
$script:clickTimer.Add_Tick({
    $f = Get-ClickFlags
    $hold = [int]$numHold.Value
    if ($rbJeu.Checked) {
        if ([ACK.Native]::InterceptionClick([int]$numDevice.Value, [uint16]$f.ItcDown, [uint16]$f.ItcUp, $hold) -eq 0) {
            Set-Actif $false; Update-ItcStatus | Out-Null
        }
    }
    else {
        [ACK.Native]::SendInputClick([uint32]$f.Down, [uint32]$f.Up, $hold)
    }
})

$script:hotkeyTimer = New-Object System.Windows.Forms.Timer
$script:hotkeyTimer.Interval = 35
$script:hotkeyTimer.Add_Tick({
    $down = (([ACK.Native]::GetAsyncKeyState((Get-SelectedVK))) -band 0x8000) -ne 0
    if ($down -and -not $script:ToucheDown) { Set-Actif (-not $script:Actif) }
    $script:ToucheDown = $down
})

$btn.Add_Click({ Set-Actif (-not $script:Actif) })
$numDelai.Add_ValueChanged({ if ($script:Actif) { $script:clickTimer.Interval = [int]$numDelai.Value } })
$cmbTouche.Add_SelectedIndexChanged({
    if ($script:Actif) { $btn.Text = "ARRETER  ($($cmbTouche.SelectedItem))" } else { $btn.Text = "DEMARRER  ($($cmbTouche.SelectedItem))" }
})
$rbJeu.Add_CheckedChanged({ if ($rbJeu.Checked) { Update-ItcStatus | Out-Null } })
$rbNormal.Add_CheckedChanged({ if ($rbNormal.Checked) { $lblItc.Text = 'Mode normal (SendInput)'; $lblItc.ForeColor = [System.Drawing.Color]::Gray } })

$form.Add_FormClosing({
    $script:clickTimer.Stop(); $script:hotkeyTimer.Stop(); [ACK.Native]::InterceptionShutdown()
})

Set-Actif $false
$lblItc.Text = 'Mode normal (SendInput)'; $lblItc.ForeColor = [System.Drawing.Color]::Gray
$script:hotkeyTimer.Start()
[void]$form.ShowDialog()
