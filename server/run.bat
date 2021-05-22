@echo off
set "FLASK_APP=main.py"
set "FLASK_ENV=development"
py -m flask run --host=0.0.0.0
pause
