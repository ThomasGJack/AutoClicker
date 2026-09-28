@echo off
REM Lance l'Auto Clicker sans afficher de console (seule la fenetre s'affiche).
start "" powershell -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "%~dp0AutoClicker.ps1"
