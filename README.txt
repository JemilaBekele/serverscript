===============================================================================
  AFET DENTAL CARE - SERVER SCRIPTS GUIDE
  Start, stop, back up and restore the system on the server PC
===============================================================================

This folder holds the scripts that run AFET Dental Care on the server PC.
It must sit next to the two system folders, like this:

    <system folder>\
        smartdent-backend\      (the API)
        smartdent-frontend\     (the website)
        server-scripts\         (this folder)

The scripts find everything from their own location, so the system folder
can be anywhere (C:\SmartDent, D:\AFET, ...).


-------------------------------------------------------------------------------
 1. WHAT EACH FILE DOES
-------------------------------------------------------------------------------

  config.bat          Settings. The ONLY file you normally edit.
  start-system.bat    Starts the backend and the website. Restarts either one
                      10 seconds after it stops or crashes.
  stop-system.bat     Stops the backend and the website.
  RunServer.vbs       Runs start-system.bat with no window (for Task Scheduler).
  backup.bat          Backs up the database and the patient images.
  RunBackup.vbs       Runs backup.bat with no window (for Task Scheduler).
  restore.bat         Restores the database from a backup.
  install-tasks.bat   Creates the two Task Scheduler tasks for you.
  install-tasks.ps1   Used by install-tasks.bat (do not run directly).
  run-backend.bat     Used by start-system.bat (do not run directly).
  run-frontend.bat    Used by start-system.bat (do not run directly).
  logs\               Created automatically. Holds the log files.


-------------------------------------------------------------------------------
 2. FIRST-TIME SETUP (do once)
-------------------------------------------------------------------------------

 Step 1 - Install on the server PC
   - Node.js 22 LTS (nodejs.org)
   - pnpm:  open a command prompt and run   npm install -g pnpm
   - MongoDB Database Tools (for backup and restore). They install to
     C:\Program Files\MongoDB\Tools\100\bin

 Step 2 - Check the backend settings
   Open smartdent-backend\.env and make sure these lines are right:

       NODE_ENV=production
       PORT=7000
       MONGODB_URI=<your database address>
       COOKIE_SECURE=false            (only for plain http:// on the clinic network)
       CORS_ORIGIN=http://localhost:3090
       TRUST_PROXY=0
       RATE_LIMIT_ANON_MAX=1000

 Step 3 - Check the website settings
   Open smartdent-frontend\.env.production. The port must match the backend:

       NEXT_PUBLIC_API_URL=/api/v1
       API_PROXY_TARGET=http://127.0.0.1:7000

 Step 4 - Build both parts (open a command prompt)

       cd <system folder>\smartdent-backend
       npm install
       npm run build

       cd <system folder>\smartdent-frontend
       pnpm install
       pnpm build

 Step 5 - Check config.bat
   Open config.bat in Notepad. Usually you only change:

       BACKUP_ROOT    where backups go (default C:\AFET-Backups).
                      Better: a second drive or an external disk, e.g. D:\AFET-Backups
       KEEP_DAYS      how many days of database backups to keep (default 30)
       FRONTEND_PORT  website port (default 3090)

 Step 6 - Test by hand
   Double-click start-system.bat, wait about 30 seconds, then open
   http://localhost:3090 in the browser and sign in.
   Then double-click stop-system.bat.

 Step 7 - Let other computers connect
   a) Give the server PC a fixed IP address (reserve it in the router).
   b) Open PowerShell AS ADMINISTRATOR and run:

        Set-NetConnectionProfile -NetworkCategory Private
        New-NetFirewallRule -DisplayName "AFET Dental" -Direction Inbound -Protocol TCP -LocalPort 3090 -Action Allow -Profile Private

   c) On the other computers open:  http://<server-ip>:3090
      Example: http://192.168.0.142:3090
   Do NOT open port 7000 (backend) or 27017 (MongoDB) in the firewall.


-------------------------------------------------------------------------------
 3. TASK SCHEDULER (start automatically + daily backup)
-------------------------------------------------------------------------------

 OPTION A - Automatic (recommended)
   Right-click install-tasks.bat > "Run as administrator".
   It creates, in Task Scheduler under the folder "AFET Dental":

     Start System   runs at Windows start-up (1 minute delay),
                    even if nobody logs in
     Daily Backup   runs every day at 21:00; if the PC was off at 21:00,
                    it runs at the next start-up

   To use another backup time, run in PowerShell as administrator:
       .\install-tasks.ps1 -BackupTime "13:00"

 OPTION B - By hand
   Open Task Scheduler > Create Task...

   Task 1: "AFET Start System"
     General  : "Run whether user is logged on or not"
                tick "Run with highest privileges"
     Triggers : New > Begin the task: "At startup"
                (optional: Delay task for 1 minute)
     Actions  : New > Start a program
                Program/script : wscript.exe
                Add arguments  : "<system folder>\server-scripts\RunServer.vbs"
     Settings : untick "Stop the task if it runs longer than"

   Task 2: "AFET Daily Backup"
     General  : same as Task 1
     Triggers : New > Daily, at 21:00
     Actions  : Program/script : wscript.exe
                Add arguments  : "<system folder>\server-scripts\RunBackup.vbs"
     Settings : tick "Run task as soon as possible after a scheduled start
                is missed"

   Keep the quotes around the path in "Add arguments".

 Check it works: in Task Scheduler right-click the task > Run, then look
 in the logs folder (section 5).


-------------------------------------------------------------------------------
 4. DAILY USE
-------------------------------------------------------------------------------

  Start the system      double-click start-system.bat  (or RunServer.vbs for
                        no window). Running it twice is safe: it skips a part
                        that is already running.
  Stop the system       double-click stop-system.bat.
                        If Task Scheduler started it: right-click >
                        "Run as administrator".
  Restart the system    stop-system.bat, then start-system.bat.
  Open the system       http://localhost:3090 on the server,
                        http://<server-ip>:3090 on other computers.


-------------------------------------------------------------------------------
 5. LOG FILES (logs folder)
-------------------------------------------------------------------------------

  system.log     each start and stop
  backend.log    backend messages and errors
  frontend.log   website messages and errors
  backup.log     each backup: "Backup started", "Database saved",
                 "Images copied", "Backup finished" (or "FAILED: ...")

  Logs larger than 10 MB are renamed to .old and a new one is started.
  Check backup.log once a week to make sure backups finish.


-------------------------------------------------------------------------------
 6. BACKUPS
-------------------------------------------------------------------------------

  Each backup creates:

    <BACKUP_ROOT>\2026-10-21_2100\db\   database, compressed (one folder per run)
    <BACKUP_ROOT>\uploads-mirror\       patient images (X-rays, photos)

  - Database backups older than KEEP_DAYS are deleted automatically.
  - uploads-mirror only receives new and changed images. Nothing is ever
    deleted from it, so an image deleted by mistake can still be found there.
  - Backup by hand any time: double-click backup.bat.
  - The database address is read from smartdent-backend\.env (MONGODB_URI).
    If it is a cloud (Atlas) database, the backup needs internet.
  - Copy the backup folder to an external disk from time to time. A backup on
    the same disk as the system is lost if that disk fails.


-------------------------------------------------------------------------------
 7. RESTORE (recover data from a backup)
-------------------------------------------------------------------------------

  !! WARNING: the restore writes into the LIVE database named in
  !! smartdent-backend\.env. Use it only when you really need to recover.

  1. Double-click restore.bat
       - it picks the NEWEST backup automatically, or
       - to pick a certain backup, open a command prompt in this folder and run:
             restore.bat 2026-10-21_2100
  2. Choose:
       1 = Replace : the database becomes exactly the backup
                     (everything saved after the backup is lost)
       2 = Merge   : only records missing from the database are added back
  3. Type YES to start (anything else cancels without changes).
  4. The script stops the system, restores, and starts the system again.

  To restore images: copy the files you need from
  <BACKUP_ROOT>\uploads-mirror back to smartdent-backend\uploads.


-------------------------------------------------------------------------------
 8. UPDATING THE SYSTEM (new version)
-------------------------------------------------------------------------------

  1. Run backup.bat first.
  2. Run stop-system.bat (as administrator if started by Task Scheduler).
  3. Copy in the new files. NEVER overwrite:
        smartdent-backend\.env
        smartdent-backend\uploads\
  4. Build again:
        smartdent-backend  :  npm install   then  npm run build
        smartdent-frontend :  pnpm install  then  pnpm build
  5. Run start-system.bat.


-------------------------------------------------------------------------------
 9. PROBLEMS AND FIXES
-------------------------------------------------------------------------------

  Website does not open on the server
    - Look at logs\frontend.log and logs\backend.log.
    - "No standalone build"  -> run  pnpm build  in smartdent-frontend
    - "dist\server.js missing" -> run  npm run build  in smartdent-backend

  Website opens but sign-in fails
    - Backend not running: check logs\backend.log.
    - Port mismatch: PORT in smartdent-backend\.env must match the port in
      API_PROXY_TARGET in smartdent-frontend\.env.production.
      After changing .env.production, run  pnpm build  again.

  Other computers cannot open the website
    - Firewall / network set to Public (section 2, step 7).
    - The server's IP changed: give it a fixed IP.
    - Try http://<server-ip>:3090 on the server itself first.

  Staff are signed out after every reload
    - COOKIE_SECURE=false is missing in smartdent-backend\.env (plain http).

  "Too many requests" when signing in
    - Raise RATE_LIMIT_ANON_MAX in smartdent-backend\.env, then restart.

  Backup says FAILED
    - "mongodump.exe not found": install MongoDB Database Tools, or fix
      MONGO_TOOLS in config.bat.
    - "MONGODB_URI not found": check smartdent-backend\.env.
    - Cloud database: check the internet connection.

  stop-system.bat does not stop the system
    - Run it as administrator (Task Scheduler runs the system as SYSTEM).

  System restarts again and again (see backend.log)
    - Usually the database cannot be reached or a .env value is wrong.
      The error is in logs\backend.log just before "Backend stopped".

===============================================================================
