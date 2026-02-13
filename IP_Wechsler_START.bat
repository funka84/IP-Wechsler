@echo off
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0IP_Wechsler.ps1\"' -Verb RunAs -WindowStyle Hidden"
