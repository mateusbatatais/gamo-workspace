@echo off
rem Dois cliques: abre o menu do staging.sh (publicar no staging) no Git Bash.
set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not exist "%GITBASH%" (
  echo Nao achei o Git Bash. Abra o Git Bash na pasta gamo e rode: ./staging.sh
  pause
  exit /b 1
)
"%GITBASH%" -l -c "cd \"$(cygpath '%~dp0')\" && ./staging.sh; echo; read -r -p 'Enter para fechar'"
