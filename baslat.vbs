' Eczane Stok gözcüsünü gizli başlatır (Başlangıç klasöründen çağrılır)
CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\EczaneStok\gozcu.ps1""", 0, False
